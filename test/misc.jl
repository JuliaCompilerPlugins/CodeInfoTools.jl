#####
##### Misc (usually for coverage)
#####

@testset "Base.:(+) -- SSAValues" begin
    @test (+)(Core.SSAValue(1), 1) == Core.SSAValue(2)
    @test (+)(1, Core.SSAValue(1)) == Core.SSAValue(2)
end

@testset "`walk` -- misc." begin
    v = Core.NewvarNode(Core.SlotNumber(5))
    walk(x -> x isa Core.SlotNumber ? 
         Core.SlotNumber(x.id + 1) : x, v)
end

@testset "Builder -- misc." begin
    ir = code_info(g, Int)
    p = CodeInfoTools.Builder(ir)
    for (v, st) in p
    end
    display(p)
    p = CodeInfoTools.Builder(ir)
    p = identity(p)
    get_slot(p, :x)
    println()
    println(length(p))
    println()
    slot!(p, :m)
    get_slot(p, :m)
end

@testset "code_info on constructor -- misc." begin
    struct T
        i::Int
    end
    ir = code_info(T, Int)
    @test Meta.isexpr(ir.code[1], :new)
end

@testset "code_inferred -- misc." begin
    b = CodeInfoTools.Builder(g, Int)
    identity(b)
    l = λ(finish(b), 1)
    src = code_inferred(l, Int)
    display(src)
end

@testset "Coverage removal -- misc." begin
    b = CodeInfoTools.Builder()
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:call, :foo, 2))
    v = push!(b, Expr(:call, :measure, 2))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:code_coverage_effect))
    k = push!(b, Expr(:call, :measure_cmp, v, 1))
    push!(b, Core.GotoIfNot(k, 14))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Expr(:call, :foo, 2))
    push!(b, Expr(:code_coverage_effect))
    push!(b, Core.GotoNode(14))
    return!(b, nothing)
    start = finish(b)
    display(start)
    new = CodeInfoTools.Builder(start)
    for (v, st) in new
        if st isa Expr && st.head == :code_coverage_effect
            delete!(new, v)
        end
    end
    src = finish(new)
    display(src)
end
