module TestCodeInfoTools

using CodeInfoTools
using Test

f(x) = begin
    y = 10 + x
    z = 20 + y
    q = 20 + z
    return q + 50
end

@testset "code_info" begin
    ir = code_info(f, Int)
    @test ir == nothing
    ir, b = code_info(f, Tuple{Int})
    @test ir != nothing
    display(b.code)
end

@testset "iterate" begin
    ir, b = code_info(f, Tuple{Int})
    local c = 1
    for (v, st) in b
        @test v == Core.SSAValue(c)
        c += 1
    end
end

@testset "replace!" begin
    ir, b = code_info(f, Tuple{Int})
    len = length(b.code)
    for (v, st) in b
        (st isa Expr && st.head == :call) || continue
        replace!(b, v, Expr(:call, Base.:(*), st.args[2 : end]...))
    end
    @test length(b.code) == len
    for (v, st) in b
        st isa Expr && st.head == :call || continue
        @test st.args[1] == Base.:(*)
        st == Expr(:call, Base.:(*), st.args[2 : end]...)
    end
end

@testset "insert!" begin
    ir, b = code_info(f, Tuple{Int})
    len = length(b.code)
    for (v, st) in b
        st isa Expr && st.head == :call || continue
        replace!(b, v, Expr(:call, Base.:(*), st.args[2 : end]...))
    end
end

end # module
