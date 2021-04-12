module TestCodeInfoTools

using CodeInfoTools
using Test

f(x) = begin
    y = 10 + x
    z = 20 + y
    q = 20 + z
    return q + 50
end

g(x) = begin
    if x > 1
        x + g(x - 1)
    else
        return 1
    end
    while true
        println("Nice!")
    end
    return
end

@testset "code_info" begin
    ir = code_info(f, Int)
    @test ir == nothing
    ir, b = code_info(f, Tuple{Int})
    @test ir != nothing
    ir, b = code_info(g, Tuple{Int})
    @test ir != nothing
    display(b)
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

@testset "pushfirst!" begin
    ir, b = code_info(f, Tuple{Int})
    pushfirst!(b, Expr(:call, rand))
    @test length(b.code) == length(b.codelocs)
    pushfirst!(b, Expr(:call, rand))
    @test length(b.code) == length(b.codelocs)
    pushfirst!(b, Expr(:call, rand))
    @test length(b.code) == length(b.codelocs)
    @test b[8] isa Core.ReturnNode
    @test b[8].val == Core.SSAValue(7)
end

@testset "bump!" begin
    ir, b = code_info(f, Tuple{Int})
    c = deepcopy(b.code)
    len = length(b.code)
    bump!(b, 1)
    circshift!(b, -1)
    @test c == b.code
    bump!(b, 1)
    @test b[5] isa Core.ReturnNode
    @test b[5].val == Core.SSAValue(5)
    circshift!(b, -1)
    @test b[5].val == Core.SSAValue(4)
end

@testset "deleteat!" begin
    ir, b = code_info(f, Tuple{Int})
    len = length(b.code)
    c = deepcopy(b.code)
    insert!(b, 1, Expr(:call, Base.:(*), 5, 3))
    insert!(b, 3, Expr(:call, Base.:(*), 5, 3))
    deleteat!(b, 3)
    deleteat!(b, 1)
    @test length(b.code) == len
    @test c == b.code
    pushfirst!(b, Expr(:call, rand))
    @test length(b.code) == length(b.codelocs)
    pushfirst!(b, Expr(:call, rand))
    @test length(b.code) == length(b.codelocs)
    pushfirst!(b, Expr(:call, rand))
    @test length(b.code) == length(b.codelocs)
    deleteat!(b, 1)
    deleteat!(b, 1)
    deleteat!(b, 1)
    @test c == b.code
end

@testset "pushslot!" begin
    ir, b = code_info(f, Tuple{Int})
    l = deepcopy(b.code)
    pushslot!(b, :m)
    @test b[1] isa Core.NewvarNode
    @test slot(b, :m) == b[1].slot
    deleteat!(b, 1)
    c = deepcopy(b.slotnames)
    for i in 1 : 50
        pushslot!(b, gensym())
        deleteat!(b, 1)
    end
    @test c == b.slotnames
    @test l == b.code
end

end # module
