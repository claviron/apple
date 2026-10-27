# Application icon codes

An application may publish an optional `icon` string in its common Application
description. Embedded and linked applications use the same field. The client
maps the code to its own bundled asset or SF Symbol; it never opens a supplied
path, URL or arbitrary symbol name. An absent or unknown code retains the
runtime's default icon. The icon does not change the reported runtime,
frameworks, request mode, permissions or dispatch.

Codes are case-insensitive. Supported choices:

| Codes | Presentation |
| --- | --- |
| `php`, `python`, `javascript`, `lua`, `olua`, `rust` | Existing runtime brand icons |
| `laravel`, `symfony`, `fastapi`, `django`, `flask`, `nestjs` | Bundled framework brand icons |
| `react`, `vue`, `svelte`, `astro`, `nuxt` | Bundled frontend framework brand icons |
| `node`, `deno`, `typescript` | Bundled optional JavaScript ecosystem icons |
| `orbit`, `orbitive` | Orbitive's orbit symbol without its wordmark |
| `hono`, `elysia`, `express`, `fastify`, `koa`, `hapi` | Selected system symbols, not official logos |
| `starlette`, `quart`, `sanic`, `litestar`, `falcon` | Selected system symbols, not official logos |
| `server`, `terminal`, `globe`, `app` | General-purpose system icons |

For runner launches, use `icon: fastapi` in YAML or `--icon fastapi` on the CLI.
Typed launch options expose the same `icon` field. PHP and JavaScript embedded
definitions provide `.icon("laravel")` and `.icon("hono")` respectively; Lua
applications accept `icon` in their definition. Gufi also provides
`Runner::icon("fastapi")`. An Orbit JavaScript application can use:

```js
await join({ fleet: "example", name: "api", icon: "server" });
```

Frameworks are independent informational tags. Discovery does not automatically
select a framework icon; an application chooses one explicitly or keeps its
runtime icon. Empty/unknown framework tags do not change default behavior.

The bundled brand icons identify the corresponding projects. Their sources
and notices are documented in [third-party notices](../THIRD_PARTY_NOTICES.md).

React, Vue, Svelte, Astro and Nuxt use colored SVGs.
Astro retains the supplied vector outlines but omits the embedded bitmap fills;
its upper shape is dark in light mode and white in dark mode, with an orange
lower shape. These icon codes do not alter runtime or framework discovery.

The Orbit SVG retains the shapes and colors from Orbitive's `assets/logo.svg`,
with the wordmark removed and a square viewport. It is an explicit icon choice;
using Orbit transport does not automatically override an application's icon.

The Deno SVG's monochrome shape is black in light mode and white in dark mode.
Choosing `icon: deno` does not change a JavaScript application's reported runtime.
