mutable struct Statevar{S<:State} <: Number
    system::System
    calc::Function #TODO: parametrise {F<:Function}
    state::S

    name::Symbol
    alias::Union{Symbol,Nothing}
    time::Statevar

    Statevar(sy, c, ST::Type{S}; stargs...) where {S<:State} = begin
        st = S(; stargs...)
        s = new{S}(sy, c, st)
        init!(s, st; stargs...)
    end
end

init!(s, st; stargs...) = begin
    initname!(s, st; stargs...)
    inittime!(s, st; stargs...)
    s
end
initname!(s::Statevar, st::State; name, alias=nothing, stargs...) = (s.name = name; s.alias = alias)
inittime!(s::Statevar, st::State; time, stargs...) = (s.time = time)
inittime!(s::Statevar, st::Tock; stargs...) = (s.time = s)

(s::Statevar)(args...) = s.calc(args...)

gettime!(s::Statevar{Tock}) = value(s.time.state)
gettime!(s::Statevar) = getvar!(s.time)

getvar!(s::Statevar) = begin
    t = gettime!(s)
    check!(s.state, t) && setvar!(s)
    value(s.state)
end
getvar!(s::System, n::Symbol) = getvar!(getfield(s, n))
setvar!(s::Statevar) = begin
    #println("checked! let's getvar!")
    # https://discourse.julialang.org/t/extract-argument-names/862
    # https://discourse.julialang.org/t/retrieve-default-values-of-keyword-arguments/19320
    m = methods(s.calc).ms[end]
    names = Base.method_argnames(m)[2:end]
    # https://discourse.julialang.org/t/is-there-a-way-to-get-keyword-argument-names-of-a-method/20454
    # first.(Base.arg_decl_parts(m)[2][2:end])
    # Base.kwarg_decl(first(methods(f)), typeof(methods(f).mt.kwsorter))
    f = () -> s.calc([getvar!(s.system, n) for n in names]...)

    store!(s.state, f)
    ps = poststore!(s.state, f)
    !isnothing(ps) && queue!(s.system.context, ps, priority(s.state))
end

import Base: convert, promote_rule
convert(T::Type{S}, s::Statevar) where {S<:Statevar} = s
convert(T::Type{V}, s::Statevar) where {V<:Number} = convert(T, getvar!(s))
promote_rule(::Type{S}, T::Type{V}) where {S<:Statevar, V<:Number} = T

import Base: ==
==(s1::Statevar, s2::Statevar) = (value(s1.state) == value(s2.state))

import Base: show
show(io::IO, s::Statevar) = print(io, "$(s.system)<$(s.name)> = $(s.state.value)")

export System, Statevar, getvar!, setvar!
