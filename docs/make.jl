using Documenter
using SnoopCompile

makedocs(
    sitename = "SnoopCompile",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    modules = [SnoopCompile],
    pages = ["index.md", "snoopi.md", "snoopc.md", "userimg.md", "reference.md"]
)

deploydocs(
    repo = "github.com/timholy/SnoopCompile.jl.git"
)
