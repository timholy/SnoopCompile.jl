"""
OptimizeMeFixed is the "improved" version of OptimizeMe. See the file in this same directory for details.
"""
module OptimizeMeFixed

struct Container{T}
    value::T
end

function lotsa_containers()
    list = Any[1, 0x01, 0xffff, 2.0f0, 'a', [0], ("key", 42)]
    cs = Container{Any}.(list)
    println("lotsa containers:")
    display(cs)
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

struct Object
    x::Int
end
Base.show(io::IO, o::Object) = print(io, "Object x: ", o.x)

function makeobjects()
    xs = [1:5; 7:7]
    return Object.(xs)
end

function main()
    lotsa_containers()
    println(contain_concrete(3.14, "is great"))
    list = [2.718, "is jealous"]
    println(contain_list(list))
    display(makeobjects())
end


end
