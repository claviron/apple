import Foundation

/// Client-owned icon vocabulary. A server supplies a code, not an asset path
/// or an SF Symbol name. Unknown codes preserve the runtime's default icon.
struct ApplicationIconPresentation {
    private let code: String?
    private let runtime: ApplicationRuntimePresentation

    init(_ code: String?, runtime: String?) {
        self.code = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtime = ApplicationRuntimePresentation(runtime)
    }

    var title: String? { runtime.title }

    var assetImage: String? {
        switch code {
        case "php": "TaskIconPHP"
        case "python": "TaskIconPython"
        case "javascript": "TaskIconJavaScript"
        case "lua", "olua": "TaskIconLua"
        case "rust": "TaskIconRust"
        case "orbit", "orbitive": "RuntimeIconOrbit"
        case "laravel": "FrameworkIconLaravel"
        case "symfony": "FrameworkIconSymfony"
        case "fastapi": "FrameworkIconFastAPI"
        case "django": "FrameworkIconDjango"
        case "flask": "FrameworkIconFlask"
        case "nestjs": "FrameworkIconNestJS"
        case "react": "FrameworkIconReact"
        case "vue": "FrameworkIconVue"
        case "svelte": "FrameworkIconSvelte"
        case "astro": "FrameworkIconAstro"
        case "nuxt": "FrameworkIconNuxt"
        case "node": "RuntimeIconNode"
        case "deno": "RuntimeIconDeno"
        case "typescript": "RuntimeIconTypeScript"
        case "server", "terminal", "globe", "app",
             "hono", "elysia", "express", "fastify", "koa", "hapi",
             "starlette", "quart", "sanic", "litestar", "falcon": nil
        default: runtime.assetImage
        }
    }

    var systemImage: String {
        switch code {
        case "server": "server.rack"
        case "terminal": "terminal"
        case "globe": "globe"
        case "app": "app.fill"
        case "hono": "flame.fill"
        case "elysia": "sparkles"
        case "express": "curlybraces"
        case "fastify": "bolt.fill"
        case "koa": "leaf.fill"
        case "hapi": "heart.fill"
        case "starlette": "star.fill"
        case "quart": "square.stack.3d.up.fill"
        case "sanic": "hare.fill"
        case "litestar": "star.circle.fill"
        case "falcon": "bird.fill"
        default: runtime.systemImage
        }
    }
}
