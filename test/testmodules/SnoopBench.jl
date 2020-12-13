module SnoopBench

# Assignment of parcel to modules
struct A end
f3(::A) = 1
f2(a::A) = f3(a)
f1(a::A) = f2(a)

# Like map! except it uses push!
# With a single call site
mappushes!(f, dest, src) = (for item in src push!(dest, f(item)) end; return dest)
mappushes(@nospecialize(f), src) = mappushes!(f, [], src)
function mappushes3!(f, dest, src)
    # A version with multiple call sites
    item1 = src[1]
    push!(dest, item1)
    item2 = src[2]
    push!(dest, item2)
    item3 = src[3]
    push!(dest, item3)
    return dest
end
mappushes3(@nospecialize(f), src) = mappushes3!(f, [], src)

# Useless specialization
function spell_spec(::Type{T}) where T
    name = Base.unwrap_unionall(T).name.name
    str = ""
    for c in str
        str *= c
    end
    return str
end
function spell_unspec(@nospecialize(T))
    name = Base.unwrap_unionall(T).name.name
    str = ""
    for c in str
        str *= c
    end
    return str
end

end
