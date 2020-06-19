module TestPackage5
export hello5, domath5

hello5(who::String) = "Hello, $who"
domath5(x::Number) = x + 5
end
