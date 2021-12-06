


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

A structured type the represents a Fame scalar or series.
"""
mutable struct FameObject{CL, FT, FR, DT}
    name::String
    # class::CL
    # type::FT
    # freq::FR
    first_index::Ref{FameIndex}
    last_index::Ref{FameIndex}
    first_period::Ref{Period{FR}}
    last_period::Ref{Period{FR}}
    data::DT
end

function FameObject(name, cl, ty, fr, fi=-1, li=-1)
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
             _ty == :date ? Int32 :
             _ty == :namelist ? String : 
             # otherwise _ty is a frequency, so the value is a date
             FameDate
    T = _cl == :series ? Vector{ElType} :
        _cl == :scalar ? Ref{ElType} :
            throw(ArgumentError("Can't handle class $cl."))
    # return FameObject{_cl, _ty, _fr, T}(name, _cl, _ty, _fr, Period{_fr}(-1), Period{_fr}(-1), T())
    return FameObject{_cl, _ty, _fr, T}(name, Ref(fi), Ref(li), Ref{Period{_fr}}(), Ref{Period{_fr}}(), T())
end

function Base.show(io::IO, fo::FameObject{CL, TY, FR,DT}) where {CL,TY,FR,DT}
    print(io, fo.name, ": ", join((CL, TY, FR, fo.first_period[],fo.last_period[]), ","))
end

getfreq(::FameObject{CL, FT, FR, DT}) where {CL, FT, FR, DT} = FR



# """
#     FameDateYMD

# Structure type that holds information about a date. It includes the year,month
# and day.
# """
# struct FameDateYMD
#     year::Int32 
#     month::Int32
#     day::Int32
# end
# Base.show(io::IO, dateYMD::FameDateYMD) = print(io, "$(dateYMD.day)/$(dateYMD.month)/$(dateYMD.year)")


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
    fo = FameObject(name, cl[], ty[], fr[], findex[], lindex[])
    fo.first_period[] = Period{getfreq(fo)}(findex[])
    fo.last_period[] = Period{getfreq(fo)}(lindex[])
    return fo
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
            cl = Ref{Cint}(-1)
            ty = Ref{Cint}(-1)
            fr = Ref{Cint}(-1)
            fi = Ref{Clonglong}(-1)
            li = Ref{Clonglong}(-1)
            status = @fame_call(fame_get_next_wildcard,
                (Cint, Cstring, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Clonglong}, Ref{Clonglong}, Cint, Ref{Cint}),
                wc_key.x, name, cl, ty, fr, fi, li, length(name) - 1, C_NULL)
            if status == HNOOBJ
                break
            elseif status == HTRUNC
                println("Object name too long and truncated $name")
            else
                check_status(status)
            end
            # FAME pads the string with \0 on the right to the length we gave.
            name = strip(name, '\0')
            fo = FameObject(name, cl[], ty[], fr[], fi[], li[])
            fo.first_period[] = Period{getfreq(fo)}(fi[])
            fo.last_period[] = Period{getfreq(fo)}(li[])
            push!(ret, fo)
            # println(name, " => ", cl[], " ", ty[], " ", fr[], " ", fp[], " ", lp[])
            # push!(ob, QuickInfo(name, cl[], ty[], fr[], FameIndex(fp[]), FameIndex(lp[])))
        end
    finally
        @fame_call(fame_free_wildcard, (Cint,), wc_key[])
    end
    return ret
end



# const HNLALL = Int32(-1)

# function isfameoname(s::AbstractString) 
#     s = strip(s)
#     if length(s) > 242 || length(s) == 0 return false end
#     c = first(s)
#     if !(isletter(c) || c ∈ ('$', '@')) return false end
#     for c in Iterators.drop(s,1)
#         # NOTE: Base.isnumeric is different from FAME.isnumeric.
#         # Since we don't export our isnumeric, we must be explicit when we want to use the one in Base.
#         if !(isletter(c) || Base.isnumeric(c) || occursin(c, "\$%#@_.")) return false end
#     end
#     # TODO: check if s is a FAME reserved word and if so return false
#     return true
# end
# function isfameoname(ss::AbstractArray{S}) where S <: AbstractString
#     for s in ss 
#         isfameoname(s) || return false
#     end
#     return true
# end

# isnamelist(s::AbstractString) = occursin(',', s) && isfameoname(split(strip(s,['{','}']), ','))

