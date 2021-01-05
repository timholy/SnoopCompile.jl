"""
OptimizeMe is a demonstration module used in illustrating how to improve code and generate effective `precompile` directives.
It has deliberate weaknesses in its design, and the analysis of these weaknesses via `@snoopi_deep` is discussed
in the documentation.
"""
module OptimizeMe

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
    cs = Container.(list)
    return concat_string(cs...)
end

function lotsa_containers()
    list = [1, 0x01, 0xffff, 2.0f0, 'a', [0], ("key", 42)]
    cs = Container.(list)
    println("lotsa containers:")
    display(cs)
end

struct Object
    x::Int
end
Base.show(io::IO, o::Object) = print(io, "Object x: ", o.x)

function makeobjects()
    xs = [1:5; 7]
    return Object.(xs)
end

function main()
    println(contain_concrete(3.14, "is great"))
    list = [2.718, "is jealous"]
    println(contain_list(list))
    lotsa_containers()
    display(makeobjects())
end

end
