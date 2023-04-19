module StaleB

# StaleB does not know about StaleC when it is being built.
# However, if StaleC is loaded first, we get `"insert_backedges"`
# invalidations.
using StaleA

# This will be invalidated if StaleC is loaded
useA() = StaleA.stale("hello")
useA2() = useA()
useA3() = useA2()

# force precompilation
begin
    Base.Experimental.@force_compile
    useA3()
end

end
