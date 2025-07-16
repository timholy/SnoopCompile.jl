module InvalidC

using InvalidA
InvalidA.f(::Int) = 2
InvalidA.f(::String) = 3
InvalidA.f(::Signed) = 4

end
