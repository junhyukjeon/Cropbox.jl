mutable struct Drive{V} <: State{V}
    value::V
end

Drive(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    #V = promote_type(V, typeof(v))
    Drive{V}(v)
end

constructortags(::Val{:Drive}) = (:unit,)

genvartype(v::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}

geninit(v::VarInfo, ::Val{:Drive}) = begin
    #HACK: needs quot if key is a symbol from VarInfo name
    k = gettag(v, :key, Meta.quot(v.name))
    b = genbody(v)
    u = gettag(v, :unit)
    @q $C.unitfy($C.value($b[$k]), $C.value($u))
end

genupdate(v::VarInfo, ::Val{:Drive}, ::MainStep) = begin
    #HACK: needs quot if key is a symbol from VarInfo name
    k = gettag(v, :key, Meta.quot(v.name))
    @gensym s f d
    @q let $s = $(symstate(v)),
           $f = $(genbody(v)),
           $d = $C.value($f[$k])
        $C.store!($s, $d)
    end # value() for Var
end
