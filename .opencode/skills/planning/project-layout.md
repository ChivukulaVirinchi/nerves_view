# Project Layout — depth reference

First decision in any new Elixir project: how to lay it out.

> **Routing:** [SKILL.md](SKILL.md) §2 — Master Decision Table, row 3.1 (Project layout).

---

## 1. Single Mix application — the default

One `lib/` tree, organized by domain boundaries. This works for Phoenix web apps, Nerves firmware, CLI tools, and pure OTP services alike.

```
my_app/
├── lib/
│   ├── my_app/                   # Domain layer
│   │   ├── application.ex        # Supervision tree
│   │   ├── repo.ex               # Ecto Repo
│   │   ├── accounts.ex           # Context — public API
│   │   ├── accounts/
│   │   │   ├── user.ex           # Schema (internal — @moduledoc false)
│   │   │   └── token.ex
│   │   ├── catalog.ex
│   │   ├── catalog/
│   │   │   ├── product.ex
│   │   │   └── category.ex
│   │   ├── mailer.ex             # Behaviour
│   │   └── mailer/
│   │       └── swoosh.ex         # Adapter
│   └── my_app_web/               # Interface layer (Phoenix)
│       ├── endpoint.ex
│       ├── router.ex
│       ├── controllers/
│       ├── live/
│       └── components/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   └── runtime.exs
├── test/
└── mix.exs
```

**When it's sufficient:** Most applications. Contexts provide domain boundaries without the overhead of multiple apps. Scale by adding contexts, not apps.

**How to grow it:** Add new context files (`lib/my_app/orders.ex`) and their internal modules (`lib/my_app/orders/*.ex`). No restructuring needed until you hit a team-boundary or deployment-boundary problem.

## 2. Umbrella project — multiple apps, shared config

Multiple OTP applications in one repository sharing build artifacts, deps, and config:

```
my_platform/                        # Root — no code here
├── apps/
│   ├── core/                       # Domain logic
│   │   ├── lib/core/
│   │   │   ├── accounts.ex
│   │   │   └── billing.ex
│   │   └── mix.exs
│   ├── core_web/                   # Phoenix web layer
│   │   ├── lib/core_web/
│   │   │   ├── endpoint.ex
│   │   │   └── router.ex
│   │   └── mix.exs                 # deps: [{:core, in_umbrella: true}]
│   └── worker/                     # Background processing
│       └── mix.exs                 # deps: [{:core, in_umbrella: true}]
├── config/config.exs               # Shared config for ALL apps
├── mix.exs                         # apps_path: "apps"
└── mix.lock                        # Single lockfile
```

**Root `mix.exs`:**

```elixir
defmodule MyPlatform.MixProject do
  use Mix.Project
  def project, do: [apps_path: "apps", version: "0.1.0", deps: deps()]
  defp deps, do: []   # Shared deps go here; app-specific deps in child mix.exs
end
```

**Child `mix.exs`:**

```elixir
defmodule Core.MixProject do
  use Mix.Project
  def project do
    [
      app: :core,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: [{:ecto, "~> 3.12"}]     # App-specific deps
    ]
  end
end
```

**Key properties:**

- Single `mix test` runs all apps; `mix test --app core` runs one
- Single `config/config.exs` for all apps — shared configuration
- Sibling deps via `in_umbrella: true`
- All apps share the same dependency versions (no version conflicts)
- `mix new my_platform --umbrella` scaffolds the structure

**When umbrella wins:** Multiple teams working on distinct subsystems. Separate deployment targets (web vs worker vs API). Hard compile-time module boundaries.

**When umbrella loses:** Single team, single deploy. The split creates maintenance overhead with little benefit. Stay with single Mix app + contexts.

## 3. Poncho project — full independence

Independent Mix projects in one repository linked by path dependencies:

```
my_platform/
├── core/                           # Independent project
│   ├── lib/core/
│   ├── config/config.exs           # Own config
│   ├── mix.exs
│   └── mix.lock
├── web/
│   └── mix.exs                     # deps: [{:core, path: "../core"}]
└── worker/
    └── mix.exs                     # deps: [{:core, path: "../core"}]
```

**Differences from umbrella:**

- Each app has its own config, deps, and lockfile
- Different apps can use different dep versions
- No shared build directory — fully independent compilation
- No `mix test` from root — test each app separately

**When poncho wins:** Apps need different dependency versions. Apps have different release cycles. Migrating toward fully independent Hex packages. Teams need complete autonomy.

## 4. Library vs application architecture

**A library is code you publish for others to consume** (Hex package, path dep in another project). **An application is code you deploy as a running system** (Mix release).

| Dimension | Application | Library |
|---|---|---|
| Owns supervision tree | Yes | No — added as child to someone else's tree |
| Configuration | `Application.get_env` in `runtime.exs`, `Application.compile_env` in `config.exs` | Accepts config via function arguments; optionally `Application.get_env` at runtime only |
| Framework dependencies | Can depend on Phoenix/Ecto/etc. | Framework-agnostic, or optional integration |
| Behaviour for swap | Config-driven | Consumer passes implementation module |
| Global state | Named GenServers, `Application.ensure_started` | Accepts registry/PubSub refs as options |

**Library rules:**

1. **Never use `Application.compile_env` in a library** — consumers can't reconfigure after compilation. Use `Application.get_env` at runtime or accept config as arguments.
2. **Never hardcode global names** — `name: __MODULE__` means only one instance can run. Accept a name option.
3. **Minimize dependencies** — each dep is a liability for your consumers.
4. **Define extension via behaviours** — let consumers customize, don't hardcode implementations.
5. **Ship a default implementation** — a useful library works out of the box AND can be customized.

```elixir
# BAD — library assumes it owns the world
defmodule MyLib.Worker do
  use GenServer
  def start_link(_) do
    GenServer.start_link(__MODULE__, Application.get_env(:my_lib, :config), name: __MODULE__)
    #                                                                      ^^^^^^^^^^^^^^ hardcoded
  end
end

# GOOD — library is a guest in someone else's application
defmodule MyLib.Worker do
  use GenServer
  def start_link(opts) do
    {config, server_opts} = Keyword.split(opts, [:buffer_size, :flush_interval])
    GenServer.start_link(__MODULE__, config, server_opts)
  end

  def child_spec(opts) do
    %{id: opts[:id] || __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end
end
```

## 5. Layout decision guide

| Signal | Layout |
|---|---|
| Single team, one deployable | Single Mix app + contexts |
| Multiple teams, hard compile-time boundaries | Umbrella |
| Apps need different dep versions | Poncho |
| Extracting a library for Hex | Poncho, then eventual Hex package |
| "Should I split?" uncertainty | **Don't split.** Use contexts inside a single app. |
| Feels like it's getting big | **Don't split.** Add contexts. |
| Code genuinely can't compile together | Umbrella or poncho (rare — usually indicates broken contexts) |

**Rule:** prefer single app + contexts until a concrete, non-ergonomic reason forces a split. Splitting is the hardest architectural decision to reverse.

---

## 6. Cross-references

- [SKILL.md](SKILL.md) §2 row 3.1 — project layout decision table
- [architecture-patterns.md](architecture-patterns.md) §3 — modular monolith as the default
- [growing-evolution.md](growing-evolution.md) §5.7 — when to extract to umbrella
- [process-topology.md](process-topology.md) §9 — OTP application boundaries in umbrella projects

---

**End of project-layout.md.** For the modular monolith deep dive, see [architecture-patterns.md](architecture-patterns.md). For when to split or grow, see [growing-evolution.md](growing-evolution.md).
