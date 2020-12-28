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

# "Soft" piracy for precompilability
function Base.show(io::IO, mime::MIME"text/plain", X::Vector{Container{T}}) where T
    invoke(show, Tuple{IO, MIME"text/plain", AbstractArray}, io, mime, X)
end
function Base.show(io::IO, mime::MIME"text/plain", X::Vector{Object})
    invoke(show, Tuple{IO, MIME"text/plain", AbstractArray}, io, mime, X)
end

function main()
    println(contain_concrete(3.14, "is great"))
    list = [2.718, "is jealous"]
    println(contain_list(list))
    lotsa_containers()
    display(makeobjects())
end

if Base.VERSION >= v"1.4.2"
    Base.precompile(Tuple{typeof(main)})   # time: 0.39872032
    Base.precompile(Tuple{typeof(show),IOContext{Base.TTY},MIME{Symbol("text/plain")},Vector{Container{Any}}})   # time: 0.14666735
    Base.precompile(Tuple{typeof(show),IOContext{Base.TTY},MIME{Symbol("text/plain")},Vector{Object}})   # time: 0.10149027
end

end
