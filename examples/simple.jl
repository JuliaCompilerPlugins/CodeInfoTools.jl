module Simple

using CodeInfoTools

function f(x, y)
    z = 10
    return x + y + z
end

ir, b = code_info(f, Tuple{Int, Int})
display(ir)
display(CodeInfoTools.transform(b))

end # module
