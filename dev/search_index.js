var documenterSearchIndex = {"docs":
[{"location":"#API-Documentation","page":"API Documentation","title":"API Documentation","text":"","category":"section"},{"location":"","page":"API Documentation","title":"API Documentation","text":"Below is the API documentation for CodeInfoTools.jl","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"CurrentModule = CodeInfoTools","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"code_info\nVariable\nStatement\nCanvas\nBuilder\niterate\nvalidate_code\nfinish","category":"page"},{"location":"#CodeInfoTools.code_info","page":"API Documentation","title":"CodeInfoTools.code_info","text":"code_info(f::Function, tt::Type{T}; generated = true, debuginfo = :default) where T <: Tuple\ncode_info(f::Function, t::Type...; generated = true, debuginfo = :default)\n\nReturn lowered code for function f with tuple type tt. Equivalent to InteractiveUtils.@code_lowered – but a function call and requires a tuple type tt as input.\n\n\n\n\n\n","category":"function"},{"location":"#CodeInfoTools.Variable","page":"API Documentation","title":"CodeInfoTools.Variable","text":"const Variable = Core.SSAValue\nvar(id::Int) = Variable(id)\n\nAlias for Core.SSAValue – represents a primitive register in lowered code. See the section of Julia's documentation on lowered forms for more information.\n\n\n\n\n\n","category":"type"},{"location":"#CodeInfoTools.Statement","page":"API Documentation","title":"CodeInfoTools.Statement","text":"struct Statement{T}\n    node::T\n    type::Any\nend\n\nA wrapper around Core nodes with an optional type field to allow for user-based local propagation and other forms of analysis. Usage of Builder or Canvas will automatically wrap or unwrap nodes when inserting or calling finish – so the user should never see Statement instances directly unless they are working on type propagation.\n\nFor more information on Core nodes, please see Julia's documentation on lowered forms.\n\n\n\n\n\n","category":"type"},{"location":"#CodeInfoTools.Canvas","page":"API Documentation","title":"CodeInfoTools.Canvas","text":"struct Canvas\n    defs::Vector{Tuple{Int, Int}}\n    code::Vector{Any}\n    codelocs::Vector{Int32}\nend\nCanvas() = Canvas(Tuple{Int, Int}[], [], Int32[])\n\nA Vector-like abstraction for Core code nodes.\n\nProperties to keep in mind:\n\nInsertion anywhere is slow.\nPushing to beginning is slow.\nPushing to end is fast.\nDeletion is fast. \nAccessing elements is fast.\nSetting elements is fast.\n\nThus, if you build up a Canvas instance incrementally, everything should be fast.\n\n\n\n\n\n","category":"type"},{"location":"#CodeInfoTools.Builder","page":"API Documentation","title":"CodeInfoTools.Builder","text":"Builder(ir)\n\nA wrapper around a Canvas instance. Call finish when done to produce a new CodeInfo instance.\n\n\n\n\n\n","category":"type"},{"location":"#Base.iterate","page":"API Documentation","title":"Base.iterate","text":"iterate(b::Builder, (ks, i) = (pipestate(p.from), 1))\n\nIterate over the original CodeInfo and add statements to a target Canvas held by b::Builder. iterate builds the Canvas in place – it also resolves local GlobalRef instances to their global values in-place at the function argument (the 1st argument) of Expr(:call, ...) instances. iterate is the key to expressing idioms like:\n\nfor (v, st) in b\n    b[v] = swap(st)\nend\n\nAt each step of the iteration, a new node is copied from the original CodeInfo to the target Canvas – and the user is allowed to setindex!, push!, or otherwise change the target Canvas before the next iteration. The naming of Core.SSAValues is taken care of to allow this.\n\n\n\n\n\n","category":"function"},{"location":"#CodeInfoTools.validate_code","page":"API Documentation","title":"CodeInfoTools.validate_code","text":"validate_code(src::Core.CodeInfo)\n\nValidate Core.CodeInfo instances using Core.Compiler.validate_code. Also explicitly checks that the linetable in src::Core.CodeInfo is not empty.\n\n\n\n\n\n","category":"function"},{"location":"#CodeInfoTools.finish","page":"API Documentation","title":"CodeInfoTools.finish","text":"finish(b::Builder)\n\nCreate a new CodeInfo instance from a Builder. Renumbers the wrapped Canvas in-place – then copies information from the original CodeInfo instance and inserts modifications from the wrapped Canvas\n\n\n\n\n\n","category":"function"}]
}
