# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.

using TimeSeriesEcon


@inline readfame(dbname::AbstractString, args...; kwargs...) =
    opendb(dbname) do db
        readfame(db, args...; kwargs...)
    end

function readfame(db::FameDatabase, args...; kwargs...)
    ret = Workspace()
    for fo in listdb(db, args...; kwargs...)
        do_read!(fo, db)
        try
            ret[Symbol(lowercase(fo.name))] = unfame(fo)
        catch e
            @info "Skipped $(fo.name): $(sprint(showerror, e))"
        end
    end
    return ret
end
export readfame

@inline unfame(fo::FameObject{:scalar,:precision}) = fo.data[]
@inline unfame(fo::FameObject{:scalar,:numeric}) = fo.data[]
@inline unfame(fo::FameObject{:scalar,:string}) = fo.data[]
@inline unfame(fo::FameObject{:scalar,:boolean}) = fo.data[] != 0
@inline unfame(fo::FameObject{:scalar,:namelist}) = fo.data[]
@inline unfame(fo::FameObject{:scalar,TY}) where {TY} = _date_to_mit(TY, fo.data[])

@inline unfame(fo::FameObject{:series,:precision,FR}) where {FR} =
    TSeries(_date_to_mit(FR, fo.first_index[]), fo.data)
@inline unfame(fo::FameObject{:series,:numeric,FR}) where {FR} =
    TSeries(_date_to_mit(FR, fo.first_index[]), fo.data)
@inline unfame(fo::FameObject{:series,:boolean,FR}) where {FR} =
    TSeries(_date_to_mit(FR, fo.first_index[]), [d != 0 for d in fo.data])
@inline unfame(fo::FameObject{:series,TY,FR}) where {TY,FR} =
    TSeries(_date_to_mit(FR, fo.first_index[]), [_date_to_mit(TY, d) for d in fo.data])
@inline unfame(fo::FameObject{:series,:string,FR}) where {FR} =
    copy(fo.data) # error("Can't handle string series")

@inline _freq_from_fame(fr) =
    (
        fr = string(val_to_symbol(fr, fame_freq));
        startswith(fr, "quarterly") ? Quarterly :
        startswith(fr, "monthly") ? Monthly :
        startswith(fr, "annual") ? Yearly :
        startswith(fr, "case") ? Unit :
        error("Cannot convert FAME frequency $fr to TimeSeriesEcon.")
    )

function _date_to_mit(fr, date)
    F = _freq_from_fame(fr)
    F == Unit && return MIT{F}(date)
    y = Ref{Cint}()
    p = Ref{Cint}()
    if is_missing(date, Val(fr))
        return typenan(MIT{F})
    end
    @fame_call_check(fame_index_to_year_period,
        (Cint, FameIndex, Ref{Cint}, Ref{Cint}),
        val_to_int(fr, fame_freq), date, y, p)
    return MIT{F}(y[], p[])
end

@inline _freq_to_fame(F) =
    (
        F == Unit ? :case :
        F == Quarterly ? :quarterly_december :
        F == Monthly ? :monthly :
        F == Yearly ? :annual_december :
        error("Cannot convert TimeSeriesEcon frequency $F to a FAME frequency.")
    )

function _mit_to_date(x::MIT{F}) where {F<:Frequency}
    F == Unit && return (:case, FameIndex(Int(x)))
    fr = _freq_to_fame(F)
    if istypenan(x)
        return (fr, FAME_INDEX_NC)
    end
    yr, p = mit2yp(x)
    index = Ref{FameIndex}(-1)
    @fame_call_check(fame_year_period_to_index,
        (Cint, Ref{FameIndex}, Cint, Cint),
        val_to_int(fr, fame_freq), index, yr, p)
    return (fr, index[])
end

@inline writefame(db, x::MVTSeries; kwargs...) = writefame(db, Workspace(pairs(x)); kwargs...)
@inline writefame(dbname::AbstractString, w::Workspace; mode = :overwrite, kwargs...) =
    opendb(dbname, mode) do db
        writefame(db, w; kwargs...)
    end

function writefame(db::FameDatabase, w::Workspace; prefix = nothing, glue::AbstractString = "_")
    for (name, value) in pairs(w)
        if prefix !== nothing
            name = Symbol(prefix, glue, name)
        end
        if value isa Union{Workspace,MVTSeries}
            writefame(db, value; prefix = name, glue=glue)
        else
            try
                fo = refame(name, value)
                do_write(fo, db)
            catch e
                @info "Failed to write $(name): $(sprint(showerror, e))" e
                continue
            end
        end
    end
end
export writefame

@inline function refame(name::Symbol, value::AbstractFloat)
    return FameObject{:scalar,:precision,:undefined,Ref{Float64}}(
        string(name), Ref(0), Ref(0), Ref(Float64(value)))
end

@inline function refame(name::Symbol, value::Float32)
    return FameObject{:scalar,:numeric,:undefined,Ref{Float32}}(
        string(name), Ref(0), Ref(0), Ref(value))
end

@inline function refame(name::Symbol, value::Bool)
    return FameObject{:scalar,:boolean,:undefined,Ref{Int32}}(
        string(name), Ref(0), Ref(0), Ref(Int32(value)))
end

@inline function refame(name::Symbol, value::MIT)
    (fr, ind) = _mit_to_date(value)
    return FameObject{:scalar,fr,:undefined,Ref{FameIndex}}(
        string(name), Ref(0), Ref(0), Ref(ind))
end

function refame(name::Symbol, value::String)
    ty = :string
    if length(value) > 1 && value[1] == '{' && value[end] == '}'
        ty = :namelist
    end
    return FameObject{:scalar,ty,:undefined,Ref{String}}(
        string(name), Ref(0), Ref(0), Ref(value))
end

function refame(name::Symbol, value::AbstractVector{<:AbstractString})
    return FameObject{:series,:string,:case,Vector{String}}(
        string(name), Ref(1), Ref(length(value)), String[value...]
    )
end

@inline refame(name::Symbol, value) =
    error("Cannot write type $(typeof(value)) to FAME database.")

function refame(name::Symbol, value::TSeries)
    if isempty(value)
        fr = _freq_to_fame(frequencyof(value))
        find = lind = FAME_INDEX_NC
    else
        (fr, find) = _mit_to_date(firstdate(value))
        lind = find + length(value) - 1
    end
    ElType = eltype(value)
    if ElType == Float32
        ty = :numeric
        val = value.values
    elseif ElType == Float64
        ty = :precision
        val = value.values
    elseif ElType <: MIT
        ty = _freq_to_fame(frequencyof(ElType))
        val = [_mit_to_date(x)[2] for x in value.values]
    elseif ElType == Bool
        ty = :boolean
        val = [Int32(x) for x in value.values]
    else
        ty = :precision
        val = [Float64(x) for x in value.values]
    end
    return FameObject{:series,ty,fr,typeof(val)}(
        string(name), Ref(find), Ref(lind), val)
end



const HNMVAL = Int32(0) # Normal value; not missing or magic
const HNCVAL = Int32(1) # Missing NC - Not Computable
const HNAVAL = Int32(2) # Missing NA - Not Available
const HNDVAL = Int32(3) # Missing ND - Not Defined
const HMGVAL = Int32(4) # Magic value; for internal use only

function is_missing(x, ::Val{:precision})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmispm, (Cdouble, Ref{Cint}), Float64(x), mt)
    return mt[] != HNMVAL
end

function is_missing(x, ::Val{:numeric})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmisnm, (Cfloat, Ref{Cint}), Float32(x), mt)
    return mt[] != HNMVAL
end

function is_missing(x, ::Val{:boolean})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmisbm, (Cint, Ref{Cint}), Int32(x), mt)
    return mt[] != HNMVAL
end

function is_missing(x, ::Val{:string})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmissm, (Cstring, Ref{Cint}), String(strip(x, '\0')), mt)
    return mt[] != HNMVAL
end

function is_missing(x, ::Val{FR}) where {FR}
    mt = Ref{Int32}(-1)
    @fame_call_check(fame_date_missing_type, (Clonglong, Ref{Cint}), Int64(x), mt)
    return mt[] != HNMVAL
end


