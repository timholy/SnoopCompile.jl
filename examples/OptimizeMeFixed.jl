"""
OptimizeMe is a demonstration module used in illustrating how to improve code and generate effective `precompile` directives.
It has deliberate weaknesses in its design, and the analysis of these weaknesses via `@snoopi_deep` is discussed
in the documentation.
"""
module OptimizeMeFixed

struct Container{T}
    value::T
end

concat_string(c1::Container, c2::Container) = string(c1.value) * ' ' * string(c2.value)

function contain_concrete(item1, item2)
    c1 = Container(item1)
    c2 = Container(item2)
    return concat_string(c1, c2)
end

function contain_list(list)
    length(list) == 2 || throw(DimensionMismatch("list must have length 2"))
    item1 = convert(Float64, list[1])::Float64
    item2 = list[2]::String
    return contain_concrete(item1, item2)
end

function lotsa_containers()
    list = Any[1, 0x01, 0xffff, 2.0f0, 'a', [0], ("key", 42)]
    cs = Container{Any}.(list)
    println("lotsa containers:")
    display(cs)
end

struct Object
    x::Int
end
Base.show(io::IO, o::Object) = print(io, "Object x: ", o.x)

function makeobjects()
    xs = [1:5; 7:7]
    return Object.(xs)
end

# "Stub" callers for precompilability
function warmup()
    mime = MIME("text/plain")
    io = Base.stdout::Base.TTY
    v = [Container{Any}(0)]
    show(io, mime, v)
    show(IOContext(io), mime, v)
    v = [Object(0)]
    show(io, mime, v)
    show(IOContext(io), mime, v)
    return nothing
end

function main()
    println(contain_concrete(3.14, "is great"))
    list = [2.718, "is jealous"]
    println(contain_list(list))
    lotsa_containers()
    display(makeobjects())
end

if Base.VERSION >= v"1.4.2"
    @assert precompile(Tuple{typeof(main)})   # time: 0.4204474
    @assert precompile(Tuple{typeof(warmup)})
end

end
