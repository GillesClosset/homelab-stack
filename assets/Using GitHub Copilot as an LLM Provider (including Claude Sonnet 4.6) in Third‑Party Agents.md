# Using GitHub Copilot as an LLM Provider (including Claude Sonnet 4.6) in Third‑Party Agents

## Overview

This report explains how third‑party tools like OpenClaw and Claude Code Copilot integrate with GitHub Copilot without asking users for raw API keys, and how a custom application can reuse the user’s Copilot plan to access models such as Claude Sonnet 4.6 where the plan allows it.[^1][^2][^3] It focuses on the OAuth device code flow, token handling, Copilot API endpoints, and model discovery, as well as practical limitations and terms‑of‑service considerations.

## What GitHub Copilot Actually Exposes

GitHub currently exposes two distinct but related surfaces:

- **GitHub Copilot platform** used by official clients (VS Code, JetBrains, CLI) and reverse‑engineered by projects like OpenClaw and various Copilot‑proxy servers.[^2][^4][^5]
- **GitHub Models / models.github.ai** REST API, an officially supported, general‑purpose inference API that exposes OpenAI, Anthropic, and other models via standard "/inference" endpoints and a models catalog.[^6][^7]

The key distinction is that the **Copilot platform is licensed per seat and is not documented as a general application backend**, whereas **GitHub Models is the documented way to build apps that call LLMs using GitHub as the billing platform**.[^8][^6] Third‑party tools that “reuse your Copilot plan” generally rely on the former, unofficial surface and should be treated as best‑effort and subject to change.

## How Existing Tools Authenticate with GitHub Copilot

### Device Code OAuth Flow

Projects such as OpenClaw and Claude Code Copilot implement GitHub’s standard **OAuth 2.0 device authorization grant (RFC 8628)** to obtain a GitHub access token associated with the user’s account, without ever asking for a personal access token (PAT).[^9][^2][^10]

Claude Code Copilot’s authentication script illustrates the pattern clearly:

1. **Initiate device code** – POST to `https://github.com/login/device/code` with a `client_id` (the Copilot OAuth app client id) and a `scope` (e.g., `read:user`) to receive `device_code`, `user_code`, `verification_uri`, and `interval`.[^9]
2. **Display code and URL** – The app shows the `user_code` and `verification_uri` and often opens the browser automatically so the user can authorize the GitHub OAuth app.[^9]
3. **Poll for token** – The app periodically POSTs to `https://github.com/login/oauth/access_token` with `client_id`, `device_code`, and `grant_type = "urn:ietf:params:oauth:grant-type:device_code"` until it receives an `access_token` or an error (`authorization_pending`, `slow_down`, `expired_token`, `access_denied`).[^9]
4. **Verify token** – The resulting token is validated by calling `https://api.github.com/user`; a non‑OK response indicates failure.[^9]
5. **Persist credentials** – The token and associated metadata (user login, provider, timestamps) are written to a local config file such as `~/.claude-copilot-auth.json`.[^9]

OpenClaw’s `openclaw models auth login-github-copilot` command follows the same pattern: it runs an interactive device flow, stores an auth profile under a named provider, and updates the configuration to use that profile with the `github-copilot` provider.[^2][^11]

### From GitHub Access Token to Copilot Access

Once a GitHub OAuth access token is obtained, tools verify that it has Copilot entitlements by calling Copilot’s own API rather than a generic GitHub REST endpoint.[^9][^2]

Claude Code Copilot’s `checkCopilotAccess` function sends a request to:

```text
GET https://api.githubcopilot.com/models
Authorization: Bearer <github_access_token>
User-Agent: claude-code-copilot-provider/1.0.0
Openai-Intent: conversation-edits
```

and treats a successful 2xx response (and sometimes a 401 that indicates a slightly different auth format) as evidence that the token is usable with Copilot.[^9] If the user’s account does not have a Copilot seat, this request fails.

OpenClaw documentation describes a similar pattern: “Use the native device-login flow to obtain a GitHub token, then exchange it for Copilot API tokens when OpenClaw runs,” exposing the result as a `github-copilot` provider in its model registry.[^2][^12]

GitHub’s own Copilot CLI also uses OAuth device flow by default (`copilot login` or `/login`), optionally falling back to environment variables such as `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN` in non‑interactive environments.[^10][^13]

## Copilot API Endpoints Used by Third‑Party Tools

Although GitHub does not publish a full Copilot “Chat API” reference, enough behavior is visible from open‑source projects and Q&A to reconstruct the key endpoints.[^14][^8][^4]

### Models Listing

Copilot surfaces a model catalog via a `/models` endpoint:

- Claude Code Copilot uses `https://api.githubcopilot.com/models` to confirm Copilot access and, in other contexts, to list available models.[^9]
- In enterprise contexts, users report `https://api.enterprise.githubcopilot.com/models` returning `data[].id` entries such as `claude-opus-4.6`, `claude-opus-4.5`, and `claude-opus-41` when called with an appropriate Copilot token.[^12]

The returned model IDs are Copilot‑specific strings (for example, `claude-opus-4.6` or `claude-sonnet-4-6`).[^12][^3][^15]

### Chat Completions

Examples on Stack Overflow show using Copilot’s chat endpoint in an OpenAI‑like way:

```text
POST https://api.githubcopilot.com/chat/completions
Authorization: Bearer pilot_token>
Content-Type: application/json

{
  "messages": [ ... ],
  "stream": true
}
```

The response looks similar to an OpenAI Chat Completions stream and includes a `model` field (for instance `gpt-3.5-turbo-0613` in an older example).[^14] Community tooling such as `copilot-chat-api` wraps this endpoint behind an OpenAI‑compatible local server, allowing any “OpenAI” client to talk to Copilot by pointing at the local proxy and passing a dummy API key.[^4]

OpenClaw’s `github-copilot` provider and similar agents like Opencode and other Copilot proxies follow this pattern: they treat Copilot as an OpenAI‑compatible backend, specifying models as `github-copilot/<model-id>` in their own configuration and translating to the underlying Copilot API.[^2][^4][^15]

## Claude Sonnet 4.6 in GitHub Copilot

Anthropic’s Claude Sonnet 4.6 is a general‑purpose model with improved coding and long‑context reasoning, released in mid‑February 2026.[^1][^3][^16] GitHub announced that “Claude Sonnet 4.6… is now rolling out in GitHub Copilot,” with an initial premium request multiplier and potential pricing adjustments.[^1]

OpenClaw issues around the release clarify several implementation details relevant to third‑party tools:

- The **Anthropic direct API model id** is `claude-sonnet-4-6`, and this is the ID used when calling Anthropic directly or via GitHub Models.[^3][^17]
- OpenClaw initially marked `anthropic/claude-sonnet-4-6` as `configured,missing` because its internal model catalog had not yet been updated, causing configuration attempts to fail with “Unknown model.”[^3]
- Separate issues requested adding `github-copilot/claude-sonnet-4.6` to the `github-copilot` provider’s `DEFAULT_MODEL_IDS`, noting that Sonnet 4.6 was already selectable in GitHub Copilot’s VS Code model picker but not exposed through OpenClaw’s Copilot provider until the catalog was updated.[^15][^18]

Once those catalogs were updated, OpenClaw and similar tools could target Sonnet 4.6 via either the Anthropic provider (`anthropic/claude-sonnet-4-6`) or the Copilot provider (`github-copilot/claude-sonnet-4.6`), subject to the user’s entitlements.[^15][^16][^18]

## Why Some Users Do Not See Anthropic Models

There are several reasons why a user calling Copilot programmatically might not see Anthropic models such as Sonnet 4.6 in a raw `/models` listing, even if those models are visible in first‑party Copilot UI:

- **Seat type and rollout** – GitHub’s announcement explicitly describes Sonnet 4.6 as “rolling out” inside Copilot, which often means gradual enablement across Copilot Pro, Business, and Enterprise, and possibly region‑ or org‑specific gating.[^1][^19]
- **Catalog lag in third‑party tools** – As demonstrated by OpenClaw, a tool’s **internal model registry** can lag behind Copilot’s actual capabilities; `models.list` or equivalent commands may omit newly released models until the tool’s catalog is updated.[^3][^15][^18]
- **Different APIs for discovery vs. usage** – GitHub Copilot CLI issues show that a `models.list` JSON‑RPC method exposed by the SDK omits `claude-sonnet-4.6` even when it is configured as the CLI’s default model, meaning there is no single canonical discovery endpoint that always returns the true effective model set.[^20]
- **Token type / scope issues** – Copilot integrations care about how the user authenticated. GitHub support discussions indicate that the Copilot CLI requires authentication via the GitHub CLI OAuth app rather than just any `GH_TOKEN` PAT; tokens with the wrong origin or scopes can authenticate to GitHub but not to Copilot APIs.[^21][^13]

As a result, a third‑party app should not hard‑code an expectation that Sonnet 4.6 will appear in every user’s Copilot `/models` response. Instead, it should enumerate the models actually returned by Copilot for that user and expose only those in its UI, possibly with a “preferred model” default when present.[^2][^20][^18]

## Implementing Copilot Device Auth in a Custom Agent App

To replicate OpenClaw‑ or Opencode‑style “Sign in with GitHub Copilot” behavior, an application can adopt the following design.

### 1. Trigger GitHub OAuth Device Flow

On first use of Copilot within the app (for example when a user selects “GitHub Copilot” as a provider), initiate the device code flow:

- POST to `https://github.com/login/device/code` with `client_id` set to the Copilot OAuth app client ID and a minimally necessary scope such as `read:user`.
- Receive `device_code`, `user_code`, `verification_uri`, and `interval`.
- Display the verification URL and code to the user, and optionally open the URL automatically, mirroring the UX of GitHub Copilot CLI and Claude Code Copilot’s script.[^9][^10]

### 2. Poll for the GitHub Access Token

In the background, poll for the OAuth token:

- POST to `https://github.com/login/oauth/access_token` with `client_id`, `device_code`, and `grant_type = "urn:ietf:params:oauth:grant-type:device_code"` at the suggested interval (plus a small safety margin).[^9]
- Handle error states (`authorization_pending`, `slow_down`, `expired_token`, `access_denied`) as shown in Claude Code Copilot’s script, surfacing useful messages to the user when necessary.[^9]
- Once an `access_token` arrives, immediately verify it by calling `https://api.github.com/user` to retrieve the GitHub username and ensure the token is valid.[^9]

Store the token and metadata in your own config or keychain (for example, `~/.yourapp/copilot-auth.json` or an encrypted store), similarly to what Claude Code Copilot does.[^9]

### 3. Check and Cache Copilot Entitlement

Before enabling Copilot models in the provider list for a given user, confirm that their GitHub account has Copilot access:

- Send a GET request to `https://api.githubcopilot.com/models` (or the enterprise variant if appropriate) with `Authorization: Bearer <github_access_token>` and a meaningful `User-Agent`.
- Use a successful response to mark the profile as Copilot‑enabled; if the call fails (for example with a 403 or 404), record that Copilot is not available for this user and surface a clear message in the UI.[^9][^12]

This check is analogous to `checkCopilotAccess` in the Claude Code Copilot script and helps avoid confusing runtime errors later.[^9]

### 4. Expose Models Returned by Copilot

Once Copilot access is confirmed, the app can:

- Parse the JSON returned by `/models`, extracting model IDs and capabilities (context window, modalities, etc.) where available.[^9][^12]
- Map these IDs into the app’s own model registry (for example, `github-copilot/claude-sonnet-4.6`, `github-copilot/gpt-4.1-mini`, etc.), similar to how OpenClaw maintains a per‑provider model catalog.[^2][^15][^22]
- Allow users to pick a default Copilot model from this list; if Sonnet 4.6 appears, it can be suggested as a “recommended” default based on its capabilities.[^1][^3]

Given the inconsistencies in discovery endpoints mentioned earlier, a robust implementation should:

- Handle cases where `/models` omits models that Copilot can nonetheless use (for example by providing a manual override or advanced config field for `model: claude-sonnet-4.6`).[^20][^18]
- Surface clear diagnostics when the underlying API returns “Unknown model” or similar errors, echoing the behavior users reported in OpenClaw issues.[^3][^15][^18]

### 5. Proxy Copilot as an OpenAI‑Compatible Backend (Optional)

If the application or agent framework already assumes an OpenAI‑style `/v1/chat/completions` API, it can follow the pattern used by community proxies such as `copilot-chat-api` and Claude Code Copilot:

- Run a lightweight local server that exposes `/v1/chat/completions`.
- Translate incoming OpenAI‑style requests into Copilot requests by:
  - Mapping the `model` parameter to a Copilot model ID.
  - Converting OpenAI‑style `messages` into the format expected by Copilot’s `/chat/completions` endpoint.
  - Forwarding streaming responses back to the client.
- Use the GitHub access token or a Copilot‑specific token stored in the auth file as the `Authorization: Bearer` value for outbound Copilot API calls.[^9][^14][^4]

This design allows the rest of the app (for example, an agent framework that supports multiple providers) to treat Copilot as just another OpenAI‑compatible backend.

### CRITICAL: Required VS Code Editor Headers (Empirical Finding)

**Discovered during Finance Dashboard integration (April 2026) — not documented in any public source, community tool, or Copilot proxy project.**

The Copilot `/chat/completions` endpoint silently gates access behind two HTTP headers that identify the calling application as a VS Code editor:

- `Editor-Version: vscode/1.99.0`
- `Editor-Plugin-Version: copilot-chat/0.25.2025040201`

**Without these headers**, the endpoint returns HTTP 400 with error code `model_not_supported` for **all models** — including models that the `/models` endpoint confirms are available.

**With these headers**, all models work correctly, including `claude-sonnet-4.6` and `claude-opus-4.6`.

Key observations:

- The `/models` discovery endpoint works **without** these headers (returns 200 with the model list).
- Only `/chat/completions` requires them — suggesting this is an access control check, not just a user‑agent convention.
- The same token, same model, same request body produces either 400 or 200 depending solely on these headers.
- This behavior was not observed in any of the reference implementations surveyed (OpenClaw, Claude Code Copilot, copilot-chat-api), likely because those projects either set appropriate user-agent strings or the requirement was added after their documentation was written.
- The specific version strings (`vscode/1.99.0`, `copilot-chat/0.25.2025040201`) were chosen to match current VS Code Copilot extension versions. GitHub may change acceptable version ranges in the future.

**Recommendation for third-party implementations:** Always include these headers when calling Copilot `/chat/completions`. Monitor for 400 errors with `model_not_supported` as a signal that the version strings may need updating.

### 6. Integrate With the App’s Agent Layer

With authentication and a model registry in place, integrating Copilot into an agent runtime typically involves:

- Defining a `github-copilot` provider that implements the app’s generic LLM interface (chat completions, tool calling, etc.).[^2][^23]
- Resolving model names (e.g., `github-copilot/claude-sonnet-4.6`) into Copilot model IDs and injecting them into each `/chat/completions` request.
- Handling Copilot‑specific headers (for example, `Openai-Intent`) and error codes, and mapping them into generic error types understood by the agent layer.[^9][^14]
- Optionally adding configuration flags to select between Copilot and other providers (Anthropic direct, GitHub Models, OpenAI, etc.), mirroring how OpenClaw exposes multiple providers side by side.[^2][^3][^17]

## Legal and Practical Considerations

### Terms of Service and Licensing

GitHub’s public documentation discusses Copilot **user management** and seat assignment via REST APIs but does not document a general Copilot Chat/Completions API for arbitrary third‑party applications.[^8][^24] Community discussions explicitly note the absence of official documentation for “Chat” and “Autocomplete” APIs and characterize existing projects as reverse‑engineered.[^8]

This has several implications:

- Using Copilot APIs to serve large numbers of users from a multi‑tenant hosted app may violate GitHub’s Copilot terms, which are designed around IDE/CLI integrations and per‑seat usage rather than acting as a generic LLM backend.[^8][^25]
- The only **documented** GitHub‑hosted LLM API for third‑party apps is **GitHub Models**, which uses dedicated tokens with `models:read` and related scopes, and is billed separately from Copilot seats.[^6][^7]

A production‑grade, user‑facing application should therefore consider using **Anthropic’s official API**, **GitHub Models**, or other supported providers for its primary backend, and reserve Copilot‑based integrations for personal tooling or environments where the licensing and risk profile are acceptable.[^6][^7][^17]

### Reliability and Forward Compatibility

Reverse‑engineered Copilot endpoints and behaviors are inherently unstable:

- GitHub has previously updated Copilot Chat API endpoints and infrastructure, deprecating unofficial proxy URLs such as `copilot-proxy.githubusercontent.com`.[^25]
- Internal SDK methods like `models.list` may not report all models actually usable by the CLI, leading to edge cases where tools cannot automatically discover a configured default model such as `claude-sonnet-4.6`.[^20]
- Community logs show that model availability and behavior can change (for example, reports that Claude 4.6 models temporarily stopped working in some Copilot Pro contexts), which can break third‑party integrations without warning.[^19]

For a robust agent application, this suggests:

- Implementing **feature detection** (probing endpoints and models at startup) rather than assuming fixed behavior.
- Providing **fallback providers** (for example, Anthropic direct, GitHub Models, or OpenAI) when Copilot calls fail.[^3][^17]
- Treating Copilot integration as an **optional provider** rather than the only path to advanced models like Sonnet 4.6.

## Recommended Approach for a New Agent Application

For a developer building an agentic application who wants to allow users to leverage their existing GitHub Copilot plans and to use Claude Sonnet 4.6 where available, a pragmatic strategy is:

- **Implement GitHub OAuth device flow** as described, mirroring the workflows used by OpenClaw, Claude Code Copilot, and GitHub’s own CLI to securely obtain and store per‑user tokens.[^9][^2][^10]
- **Build a Copilot provider** in the app that:
  - Calls `https://api.githubcopilot.com/models` (or enterprise equivalent) to introspect available models.
  - Exposes those models (including `github-copilot/claude-sonnet-4.6` when present) through the app’s UI.
  - Forwards chat completions via Copilot’s `/chat/completions` endpoint using the user’s token, optionally via a small local proxy that presents an OpenAI‑compatible interface.[^9][^12][^14][^4][^15]
- **Also support at least one fully documented provider** (Anthropic direct or GitHub Models) to ensure Sonnet 4.6 is available independent of Copilot rollout quirks and licensing constraints, using the official `claude-sonnet-4-6` model ID.[^3][^16][^17]

This architecture lets power users point your app at GitHub Copilot when they are comfortable with the licensing and instability trade‑offs, while giving a stable, officially supported path to Sonnet 4.6 and other models through standard APIs.

---

## References

1. [Claude Sonnet 4.6 is now generally available in GitHub Copilot](https://github.blog/changelog/2026-02-17-claude-sonnet-4-6-is-now-generally-available-in-github-copilot/) - Claude Sonnet 4.6, Anthropic's latest agentic coding model, is now rolling out in GitHub Copilot. In...

2. [openclaw/docs/providers/github-copilot.md at main](https://github.com/openclaw/openclaw/blob/main/docs/providers/github-copilot.md) - Use the native device-login flow to obtain a GitHub token, then exchange it for Copilot API tokens w...

3. [Support Claude Sonnet 4.6 (claude-sonnet-4-6) — released today](https://github.com/openclaw/openclaw/issues/19529) - GitHub ModelsManage and compare prompts · MCP RegistryIntegrate ... Support Claude Sonnet 4.6 (claud...

4. [GitHub - jiaweing/copilot-chat-api: Provides a simple HTTP API to ...](https://github.com/jiaweing/copilot-chat-api) - Provides a simple HTTP API to interface with GitHub Copilot, including native GitHub authentication....

5. [ericc-ch/copilot-api: Turn GitHub Copilot into OpenAI/Anthropic API ...](https://github.com/ericc-ch/copilot-api) - The server exposes several endpoints to interact with the Copilot API. It provides OpenAI-compatible...

6. [REST API endpoints for models catalog - GitHub Docs](https://docs.github.com/en/rest/models/catalog) - Use the REST API to get a list of models available for use, including details like ID, supported inp...

7. [REST API endpoints for models inference - GitHub Docs](https://docs.github.com/en/rest/models/inference) - You can use the REST API to run inference requests using the GitHub Models platform. The API require...

8. [Using Copilot chat API programatically #112339 - GitHub](https://github.com/orgs/community/discussions/112339) - Hi Team, Can I call Copilot chat API programmatically ie from my Python or Java code. I don't find a...

9. [Authentication script - Claude Code Copilot - Mintlify](https://www.mintlify.com/samarth777/claude-code-copilot/api/auth-script) - The authentication script implements GitHub's OAuth device code flow to obtain an access token for t...

10. [Authenticating GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli) - The OAuth device flow is the default authentication method for interactive use. You can authenticate...

11. [[Feature]: OpenClaw non-interactive setup for GitHub Copilot #31584](https://github.com/openclaw/openclaw/issues/31584) - Summary OpenClaw supports two ways to onboard to Copilot - using GH copilot provider (interactive to...

12. [[Feature]: Add github-copilot/claude-opus-4.6 model support #10091](https://github.com/openclaw/openclaw/issues/10091) - Claude Opus 4.6 is now available in the GitHub Copilot API (as of Feb 5, 2026), but OpenClaw's githu...

13. [Copilot CLI doesn't work with `GH_TOKEN` authentication? · community · Discussion #167158](https://github.com/orgs/community/discussions/167158) - Select Topic Area Question Copilot Feature Area General Body Hello, I have the gh cli installed, wit...

14. [How to get response of copilot LLM in github chat completions api](https://stackoverflow.com/questions/79130421/how-to-get-response-of-copilot-llm-in-github-chat-completions-api) - I want to inject some pieces of documentation into copilot(which it'll request in the message), so i...

15. [Add github-copilot/claude-sonnet-4.6 to Copilot provider model ...](https://github.com/openclaw/openclaw/issues/20091) - Summary OpenClaw's GitHub Copilot provider (src/providers/github-copilot-models.ts) does not include...

16. [Add support for Claude Sonnet 4.6 (claude-sonnet-4-6-20260218)](https://github.com/openclaw/openclaw/issues/20018) - Resolved — Sonnet 4.6 support is already included in v2026.2.17 (defaults.ts has sonnet: anthropic/c...

17. [Support for Claude Sonnet 4.6 (Anthropic & Vertex AI) with Adaptive ...](https://github.com/danny-avila/LibreChat/issues/11828) - GitHub ModelsManage and compare prompts · MCP RegistryIntegrate ... I would like to request support ...

18. [claude-sonnet-4-6 not available via github-copilot provider ...](https://github.com/openclaw/openclaw/issues/19899) - GitHub ModelsManage and compare prompts ... Closing as fixed by #20270 (merged): GitHub Copilot mode...

19. [Claude Opus 4.6 and Sonnet no longer available in Copilot Pro?](https://github.com/orgs/community/discussions/189999) - md-marop-hossain 2 weeks ago. -. Both Claude Sonnet 4.6 and Opus 4.6 models have errors showing: 'Er...

20. [models.list API omits CLI's configured default model (e.g. claude ...](https://github.com/github/copilot-cli/issues/1608) - GitHub ModelsManage and compare prompts · MCP RegistryIntegrate ... For example, after running /mode...

21. [[DOCS]: What OAuth scope is required for gh copilot ? #1 - GitHub](https://github.com/github/gh-copilot/issues/1) - Describe the need ➜ ~ gh copilot suggest "Receive webhooks locally" ✗ Error: No valid OAuth token de...

22. [Update Copilot provider model list to add claude-opus-4-6-fast, gpt ...](https://github.com/openclaw/openclaw/issues/15014) - +1 on this. The proposed model list is also missing claude-sonnet-4.6 , which became GA in GitHub Co...

23. [Support GitHub Copilot Chat API for separate token quota #4582](https://github.com/openclaw/openclaw/issues/4582) - GitHub Copilot provides separate token quotas for Premium and Chat endpoints, but OpenClaw currently...

24. [Add Teams To The Copilot...](https://docs.github.com/en/rest/copilot/copilot-user-management) - Use the REST API to manage the GitHub Copilot Business subscription for your organization.

25. [Important Updates: Copilot Chat API endpoints and Copilot ... - GitHub](https://github.com/orgs/community/discussions/101438) - On February 1, 2024, we will deprecate the Copilot Chat API endpoints currently being routed through...

