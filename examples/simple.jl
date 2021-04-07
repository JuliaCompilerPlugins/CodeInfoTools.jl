module Simple

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

ir, b = code_info(f, Tuple{Int,Int})

function transform(b)
    for (v, st) in b
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == Base.:(+) || continue
        replace!(b, v, Expr(:call, Base.:(*), st.args[2:end]...))
    end
    return finish(b)
end

display(ir)
display(transform(b))

end # module
