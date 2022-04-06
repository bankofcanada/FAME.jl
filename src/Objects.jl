# Copyright (c) 2020-2022, Bank of Canada
# All rights reserved.



"""
    struct Period{FREQ} … end

A FAME period includes the frequency, year and period. 
"""
struct Period{FREQ}
    year::Int32
    period::Int32
end

function Period{FREQ}(ind::Integer) where {FREQ}
    if iscase(FREQ)
        return Period{FREQ}(0, convert(Int32, ind))
    elseif FREQ == :undefined
        # in a scalar freq is undefined and periods are set to 0
        return Period{FREQ}(0, 0)
    elseif convert(Int64, ind) == FAME_INDEX_NC
        # in an empty series index is set to INDEX_NC and year,period to -1,-1 
        return Period{FREQ}(-1, -1)
    else
        # otherwise we call fame to convert index to year:period
        y = Ref{Int32}(-1)
        p = Ref{Int32}(-1)
        @fame_call_check(fame_index_to_year_period,
            (Cint, Clonglong, Ref{Cint}, Ref{Cint}),
            fame_freq[FREQ], convert(Int64, ind), y, p)
        return Period{FREQ}(y[], p[])
    end
end
Base.show(io::IO, p::Period) = print(io, "$(p.year):$(p.period)")

function FameIndex(p::Period{FREQ})::FameIndex where {FREQ}
    if iscase(FREQ)
        return p.period
    else
        date = Ref{Cint}(-1)
        @fame_call_check(fame_year_period_to_index, (Cint, Ref{Cint}, Cint, Cint),
            fame_freq[FREQ], date, p.year, p.period)
        return date[]
    end
end

"""
    mutable struct FameObject{CL,FT,FR,DT} … end

FAME object of class `CL`, type `FT`, frequency `FR` and data type `DT`.

A `FameObject` is returned by [`quick_info`](@ref) and a vector of
`FameObject`s is returned by [`listdb`](@ref). 

Also, a `FameObject` can be constructed directly by calling
`FameObject(name, class, type, frequency)` or
`FameObject(name, class, type, frequency, first_index, last_index)`. The values
of `class`, `type`, and `frequency` can be symbols (like, `:scalar`,
`:precision`, etc.) or integers. Refer to the FAME CHLI documentation for the
code values.
"""
mutable struct FameObject{CL,FT,FR,DT}
    # CL : fame_class
    # FT : fame_type
    # FR : fame_freq
    # DT : type of the `data` field 
    name::String
    first_index::Ref{FameIndex}
    last_index::Ref{FameIndex}
    data::DT
end
export FameObject

function FameObject(name, cl, ty, fr, fi = -1, li = -1, data = nothing)
    # When the value is a date the type is a frequency.
    _ty = try
        val_to_symbol(ty, fame_type)
    catch
        val_to_symbol(ty, fame_freq)
    end
    _cl = val_to_symbol(cl, fame_class)
    _fr = val_to_symbol(fr, fame_freq)
    ElType = _ty == :precision ? Float64 :
             _ty == :numeric ? Float32 :
             _ty == :boolean ? Int32 :
             _ty == :string ? String :
             _ty == :date ? FameDate :
             _ty == :namelist ? String :
             # otherwise _ty is a frequency, so the value is a date
             FameDate
    T = _cl == :series ? Vector{ElType} :
        _cl == :scalar ? Ref{ElType} :
        throw(ArgumentError("Can't handle class $cl."))
    if data === nothing
        return FameObject{_cl,_ty,_fr,T}(name, Ref(fi), Ref(li), T())
    else
        return FameObject{_cl,_ty,_fr,T}(name, Ref(fi), Ref(li), data)
    end
end

function Base.show(io::IO, fo::FameObject{CL,TY,FR,DT}) where {CL,TY,FR,DT}
    print(io, fo.name, ": ", join((CL, TY, FR,
            Period{getfreq(fo)}(fo.first_index[]),
            Period{getfreq(fo)}(fo.last_index[])), ","))
end

getfreq(::FameObject{CL,FT,FR,DT}) where {CL,FT,FR,DT} = FR


export quick_info
"""
    quick_info(db, name)

Get information about object named `name` in the given database. The information
inlcudes its class, type, frequency, and range. Return a [`FameObject`](@ref) in
which all these attributes are set correctly, but the data does not contain the
correct values.
"""
function quick_info(db::FameDatabase, name::String)
    cl = Ref{Cint}(-1)
    ty = Ref{Cint}(-1)
    fr = Ref{Cint}(-1)
    findex = Ref{Clonglong}(-1)
    lindex = Ref{Clonglong}(-1)
    @fame_call_check(fame_quick_info,
        (Cint, Cstring, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Clonglong}, Ref{Clonglong}),
        db.key, name, cl, ty, fr, findex, lindex)
    return FameObject(name, cl[], ty[], fr[], findex[], lindex[])
end


### List database

export listdb

"""
    item_option(name, values...)

Set ITEM option. These are used when matching a wildcard to database objects.
Option names include "CLASS", "TYPE", "FREQUENCY", "ALIAS".

When the `values` argument is not given, it defaults to "ON". Otherwise `values`
should be strings and indicate which ITEMs are to be turned on.

"""
function item_option end

function item_option(name::String, values::AbstractString...)
    uname = uppercase(strip(name))
    if isempty(values) || (length(values) == 1 && isempty(strip(values[1])))
        @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM $uname", "ON")
        return
    end
    @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM $uname", "OFF")
    for val in values
        uval = uppercase(strip(val))
        try
            @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM $uname $uval", "ON")
        catch e
            e isa HLIError && @error "Bad $(uname) $(uval)."
            rethrow()
        end
    end
end


"""
    listdb(db::FameDatabase, [wc; filters...])

List objects in the database that match the given wildcard and filters. Return a
[`Vector{FameObject}`](@ref FameObject).

The wildcard `wc` is a string containing wildcard characters. '^' matches any
one character, while '?' matches any zero or more characters. If not given, the 
default is '?' which would list the entire database.

The filters:
  * `alias::Bool` - whether or not to match alias names. 
  * `class::String` - which class of object to match. Multiple classes can be
    given in a comma-separated string, e.g., `class="SERIES,SCALAR"`.
  * `type::String` - which type of object to match, e.g., `type="NUMERIC,PRECISION"`.
  * `freq::String` - which frequency of object to match, e.g., `freq="QUARTERLY"`.
"""
function listdb end

@inline listdb(dbname::AbstractString, args...; kwargs...) =
    opendb(dbname) do db
        listdb(db, args...; kwargs...)
    end

function listdb(db::FameDatabase, wildcard::String = "?";
    alias::Bool = true, class = "", type = "", freq = "")

    class = string(class)
    type = string(type)
    freq = string(freq)

    @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM ALIAS", alias ? "ON" : "OFF")
    item_option("CLASS", split(class, ",")...)
    item_option("TYPE", split(type, ",")...)
    item_option("FREQUENCY", split(freq, ",")...)

    wc_key = Ref{Cint}(-1)
    @fame_call_check(fame_init_wildcard,
        (Cint, Ref{Cint}, Cstring, Cint, Cstring),
        db.key, wc_key, wildcard, 0, C_NULL)
    ret = FameObject[]
    try
        while true
            name = repeat(" ", 101)
            cl = Ref{Cint}()
            ty = Ref{Cint}()
            fr = Ref{Cint}()
            fi = Ref{Clonglong}()
            li = Ref{Clonglong}()
            status = @fame_call(fame_get_next_wildcard,
                (Cint, Cstring, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Clonglong}, Ref{Clonglong}, Cint, Ref{Cint}),
                wc_key[], name, cl, ty, fr, fi, li, length(name) - 1, C_NULL)
            if status == HNOOBJ
                break
            elseif status == HTRUNC
                println("Object name too long and truncated $name")
            else
                check_status(status)
            end
            # FAME pads the string with \0 on the right to the length we gave.
            name = strip(name, '\0')
            # note: fame_get_next_wildcard returns incorrect fi and li for scalars.
            @fame_call_check(fame_quick_info,
                (Cint, Cstring, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Clonglong}, Ref{Clonglong}),
                db.key, name, cl, ty, fr, fi, li)
            fo = FameObject(name, cl[], ty[], fr[], fi[], li[])
            push!(ret, fo)
        end
    finally
        @fame_call(fame_free_wildcard, (Cint,), wc_key[])
    end
    return ret
end
export listdb

