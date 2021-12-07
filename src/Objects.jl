# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.



"""
    Period

Structure type that holds information about a period. It includes the frequency
and the year:period pair.
"""
struct Period{FREQ}
    year::Int32
    period::Int32
end
Period{FREQ}(ind::Integer) where {FREQ} = 
    iscase(FREQ) ? Period{FREQ}(0, convert(Int32, ind)) :
    # in a scalar freq is undefined and periods are set to 0
    FREQ == :undefined ? Period{FREQ}(0, 0) :
    # in an empty series index is set to INDEX_NC and year,period to -1,-1 
    convert(Int64, ind) == FAME_INDEX_NC ? Period{FREQ}(-1, -1) :
    # otherwise we call fame to convert index to year:period
        let y = Ref{Int32}(-1), p = Ref{Int32}(-1)
            @fame_call_check(fame_index_to_year_period,
                (Cint, Clonglong, Ref{Cint}, Ref{Cint}),
                fame_freq[FREQ], convert(Int64, ind), y, p)
            Period{FREQ}(y[], p[])
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
    FameObject

A structured type that represents a Fame scalar or series in Julia.
"""
mutable struct FameObject{CL, FT, FR, DT}
    name::String
    # class::CL
    # type::FT
    # freq::FR
    first_index::Ref{FameIndex}
    last_index::Ref{FameIndex}
    data::DT
end

function FameObject(name, cl, ty, fr, fi=-1, li=-1, data=nothing)
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
        return FameObject{_cl, _ty, _fr, T}(name, Ref(fi), Ref(li), T())
    else
        return FameObject{_cl, _ty, _fr, T}(name, Ref(fi), Ref(li), data)
    end
end

function Base.show(io::IO, fo::FameObject{CL, TY, FR,DT}) where {CL,TY,FR,DT}
    print(io, fo.name, ": ", join((CL, TY, FR, 
        Period{getfreq(fo)}(fo.first_index[]),
        Period{getfreq(fo)}(fo.last_index[])), ","))
end

getfreq(::FameObject{CL, FT, FR, DT}) where {CL, FT, FR, DT} = FR


export quick_info
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

List objects in the database that match the given wildcard and filters.

The wildcard `wc` is a string containing wildcatd characters. 
'^' matches any one character while '?' matches any zero or more characters.

The filters:
  * `alias::Bool` - whether or not to match alias names. 
  * `class::String` - which class of object to match. Multiple classes can be
    given in a comma-separated string, e.g., `class="SERIES,SCALAR"`.
  * `type::String` - same as `class` but for the type of the object
    ("NUMERIC,PRECISION").
  * `freq::String` - same as `class` but for the frequency of the object.

"""
function listdb end

@inline listdb(dbname::AbstractString, args...; kwargs...) = 
    opendb(dbname) do db
        listdb(db, args...; kwargs...)
    end

function listdb(db::FameDatabase, wildcard::String = "?";
    alias::Bool = true, class="", type="", freq="")

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

