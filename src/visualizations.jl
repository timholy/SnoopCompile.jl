# This is loaded conditionally via @require if PyPlot is loaded

using .PyPlot: plt, PyCall

export specialization_plot

function specialization_plot(ax::PyCall.PyObject, ridata; markersz=9, t0 = 0.001, interactive::Bool=true, kwargs...)
    function onclick(event)
        xc, yc = event.xdata, event.ydata
        idx = argmin((log.(rts .+ t0) .- log(xc)).^2 + (log.(its .+ t0) .- log(yc)).^2)
        m = meths[idx]
        println(m, " ($(nspecs[idx]) specializations)")
    end

    meths, rts, its, nspecs = Union{Method,MethodLoc}[], Float64[], Float64[], Int[]
    for (m, (rt, it, nspec)) in ridata
        push!(meths, m)
        push!(rts, rt)
        push!(its, it)
        push!(nspecs, nspec)
    end
    sp = sortperm(nspecs)
    meths, rts, its, nspecs = meths[sp], rts[sp], its[sp], nspecs[sp]

    # Add t0 to each entry to handle times of zero in the log-log plot
    smap = ax.scatter(rts .+ t0, its .+ t0, markersz, nspecs; kwargs...)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Run time + $t0 (s)")
    ax.set_ylabel("Inference time + $t0 (s)")
    ax.set_aspect("equal")
    plt.colorbar(smap, label = "# specializations (incl. consts)", ax=ax)
    if interactive
        ax.get_figure().canvas.mpl_connect("button_press_event", onclick)
    end
    return ax
end

function specialization_plot(ridata; kwargs...)
    fig, ax = plt.subplots()
    return specialization_plot(ax, ridata; kwargs...)
end

specialization_plot(ax::PyCall.PyObject, tinf::InferenceTimingNode; consts::Bool=true, kwargs...) = specialization_plot(ax, runtime_inferencetime(tinf; consts); kwargs...)
specialization_plot(tinf::InferenceTimingNode; consts::Bool=true, kwargs...) = specialization_plot(runtime_inferencetime(tinf; consts); kwargs...)
