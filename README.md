# CodeInfoTools.jl

| **Build Status**                                       | **Coverage**                    | **Documentation** |
|:------------------------------------------------------:|:-------------------------------:|:-----------------:|
| [![][gha-ci-img]][gha-url] [![][gha-nightly-img]][gha-url] | [![][codecov-img]][codecov-url] | [![][dev-docs-img]][dev-docs-url] |

[gha-ci-img]: https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl/workflows/CI/badge.svg?branch=master
[gha-nightly-img]: https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl/workflows/JuliaNightly/badge.svg?branch=master
[gha-url]: https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl/actions
[codecov-img]: https://codecov.io/github/JuliaCompilerPlugins/CodeInfoTools.jl/badge.svg?branch=master
[codecov-url]: https://codecov.io/github/JuliaCompilerPlugins/CodeInfoTools.jl?branch=master
[dev-docs-img]: https://img.shields.io/badge/docs-dev-blue.svg
[dev-docs-url]: https://JuliaCompilerPlugins.github.io/CodeInfoTools.jl/dev

```
] add CodeInfoTools
```

> **Note**: A curated collection of tools for the discerning `Core.CodeInfo` connoisseur.
>
> The architecture of this package is based closely on the [Pipe construct in IRTools.jl](https://github.com/FluxML/IRTools.jl/blob/1f3f43be654a41d0db154fd16b31fdf40f30748c/src/ir/ir.jl#L814-L973). Many (if not all) of the same idioms apply.

## Motivation

Working with `Core.CodeInfo` is often not fun. E.g. when examining the untyped lowered form of the [Rosenbrock function](https://en.wikipedia.org/wiki/Rosenbrock_function)

```
CodeInfo(
    @ /Users/mccoybecker/dev/CodeInfoTools.jl/examples/simple.jl:7 within `rosenbrock'
1 ─       a = 1.0
│         b = 100.0
│         result = 0.0
│   %4  = (length)(x)
│   %5  = (-)(%4, 1)
│   %6  = (Colon())(1, %5)
│         @_3 = (iterate)(%6)
│   %8  = (===)(@_3, nothing)
│   %9  = (Core.Intrinsics.not_int)(%8)
└──       goto #4 if not %9
2 ┄ %11 = @_3
│         i = (getfield)(%11, 1)
│   %13 = (getfield)(%11, 2)
│                .
│                .
│                .
│
│   %36 = (===)(@_3, nothing)
│   %37 = (Core.Intrinsics.not_int)(%36)
└──       goto #4 if not %37
3 ─       goto #2
4 ┄       return result
)
```

Do you ever wonder -- is there another (perhaps, any) way to work with this object? A `Builder` perhaps? Where I might load my `CodeInfo` into -- iterate, make local changes, and produce a new copy?

## Contribution

`CodeInfoTools.jl` provides a `Builder` abstraction which allows you to safely iterate over and manipulate `Core.CodeInfo`. It also provides more advanced functionality for creating and evaluating `Core.CodeInfo` -- [which is a bit on the experimental side.](https://juliacompilerplugins.github.io/CodeInfoTools.jl/dev/#Evaluation)

How might you use this in practice?

```julia
using CodeInfoTools

function f(x, y)
    z = 10
    if z > 10
        n = 10
        return x + y
    else
        return x + y + z
    end
end

src = code_info(f, Int, Int)

function transform(src)
    b = CodeInfoTools.Builder(src)
    for (v, st) in b
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == Base.:(+) || continue
        b[v] = Expr(:call, Base.:(*), st.args[2:end]...)
    end
    return finish(b)
end

display(src)
display(transform(src))
```

Here, we've lowered a function directly to a `Core.CodeInfo` instance and created a `Builder` instance `b`. You can now safely iterate over this object, perform local changes, press `finish` and - _(la di da!)_ - out comes a new `Core.CodeInfo` with your changes fresh.

```
# Before:
CodeInfo(
1 ─      Core.NewvarNode(:(n))
│        z = 10
│   %3 = z > 10
└──      goto #3 if not %3
2 ─      n = 10
│   %6 = x + y
└──      return %6
3 ─ %8 = x + y + z
└──      return %8
)

# After:
CodeInfo(
1 ─      Core.NewvarNode(:(n))
│        z = 10
│   %3 = (>)(z, 10)
└──      goto #3 if not %3
2 ─      n = 10
│   %6 = (*)(x, y)
└──      return %6
3 ─ %8 = (*)(x, y, z)
└──      return %8
)
```
