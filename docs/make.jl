using Documenter
using SnoopCompile
import PyPlot   # so that the visualizations.jl file is loaded

makedocs(
    sitename = "SnoopCompile",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    modules = [SnoopCompile.SnoopCompileCore, SnoopCompile],
    linkcheck = true,
    # doctest = :fix,
    pages = ["index.md",
             "tutorial.md",
             "Modern tools" => ["snoop_invalidations.md", "snoop_inference.md", "pgdsgui.md", "snoop_inference_analysis.md", "snoop_inference_parcel.md", "jet.md"],
             "reference.md"],
)

deploydocs(
    repo = "github.com/timholy/SnoopCompile.jl.git",
    push_preview=true
)
