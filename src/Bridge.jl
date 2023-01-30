# Copyright (c) 2020-2022, Bank of Canada
# All rights reserved.

using TimeSeriesEcon


"""
    readfame(db, args...; 
        namecase=lowercase,
        prefix=nothing, glue="_",
        collect=[], 
        wc_options...)

Read data from FAME database into Julia. The data is returned in a
[`Workspace`](@ref TimeSeriesEcon.Workspace).

`db` is a [`FameDatabase`](@ref) or a `String`. If `db` is a `String`, the
database will be opened in `:readonly` mode and closed after loading the data.

If the db string containing a path to a file, the path should be encapsulated in 
escaped double quotes whenever the path contains spaces.

If `db` is the only argument, then all objects in the database will be loaded.
Arguments and options can be used to restrict which objects will be loaded.

Each positional argument after the first one should be a string or a Symbol. 
* If it is a string that contains a wildcard character (`'?'` or `'^'`, see Fame
  help about wildcards) then we call [`listdb`](@ref) to obtain a list of
  objects matching the given wildcard. In this case, we pass the given
  `wc_options...` to [`listdb`](@ref). You can use them to limit the wildcard
  search to specific class, type, frequency, etc. See [`listdb`](@ref) for
  details.
* Otherwise (Symbol or a string not containing wildcard characters), an object
  with the given name will be loaded. `wc_options...` are ignored, meaning that
  the object will be loaded no matter its class, type, frequency, etc.

The following options can be used to modify how the Julia identifiers are
constructed from the FAME names.

* `namecase` - FAME identifiers are case-insensitive and FAME always returns
  them in upper case. By default we convert the names to lower case. You can
  pass any function that takes a string and returns a string as the value of the
  `namecase` option. The default is `lowercase`. For example, this may be a good
  idea if your database contains names with symbols that are not allowed in
  Julia identifiers. Currently, we just call `Symbol(namecase(fo.name))`, but you
  may want to substitute such symbols for something else, e.g.
  `namecase=(x->lowercase(replace(x, "@"=>"_")))`.
* `prefix`, if given, will be stripped (together with `glue`) from the beginning
  of the FAME name. If the name does not begin with the given `prefix` then it
  will remain unchanged. If you want to load only names starting with the given
  prefix you must use the appropriate wildcard. Default is `prefix=nothing`,
  which disables this functionality. Note that `prefix=nothing` and `prefix=""`
  are not the same.
* `collect` can be a string/symbol, a vector whose elements are strings/symbols
  or vectors of strings/symbols, etc. If the name begins with one of the given
  `collect` values (together with the `glue`), then the object will be loaded in
  a nested [`Workspace`](@ref). The idea is that nested Workspaces written to
  the database would be loaded in the same structure by providing the list of
  names of the nested Workspaces in the `collect` option value. See the examples
  below.
* `glue` is used to join the `prefix` or the `collect` strings to the rest of
  the name. Use the same value as in [`writefame`](@ref) in order for this to
  work.

## Examples
```
julia> w = Workspace(; a = 1, b=TSeries(2020Q1, randn(10)),
       s = MVTSeries(2020M1, (:q, :p), randn(24,2)),
       c = Workspace(; alpha = 0.1, beta = 0.8, 
       n = Workspace(; s = "Hello World")
       ))
Workspace with 4-variables
  a ⇒ 1
  b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2
  s ⇒ 24×2 MVTSeries{Monthly} with range 2020M1:2021M12 and variables (q,p)
  c ⇒ Workspace with 3-variables

julia> writefame("data.db", w); listdb("data.db")
7-element Vector{FameObject}:
 A: scalar,numeric,undefined,0:0,0:0
 B: series,precision,quarterly_december,2020:1,2022:2
 C_ALPHA: scalar,precision,undefined,0:0,0:0
 C_BETA: scalar,precision,undefined,0:0,0:0
 C_N_S: scalar,string,undefined,0:0,0:0
 S_P: series,precision,monthly,2020:1,2021:12
 S_Q: series,precision,monthly,2020:1,2021:12

julia> # read only variables in the list
julia> readfame("data.db", "a", "b")
Workspace with 2-variables
  a ⇒ 1.0
  b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2

julia> # read everything as it is in the database
julia> readfame("data.db")
Workspace with 7-variables
        a ⇒ 1.0
        b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2
  c_alpha ⇒ 0.1
   c_beta ⇒ 0.8
    c_n_s ⇒ 11-codeunit String
      s_p ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12
      s_q ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12

julia> # prefix is stripped where it appears (still loading everything)
julia> readfame("data.db", prefix="c")
Workspace with 7-variables
      a ⇒ 1.0
      b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2
  alpha ⇒ 0.1
   beta ⇒ 0.8
    n_s ⇒ 11-codeunit String
    s_p ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12
    s_q ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12

julia> # wildcard search, no prefix (name remains unchanged)
julia> readfame("data.db", "s?")
Workspace with 2-variables
  s_p ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12
  s_q ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12

julia> # prefix (stripped) with matching wildcard search
julia> readfame("data.db", "s?", prefix="s")  
Workspace with 2-variables
  p ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12
  q ⇒ 24-element TSeries{Monthly} with range 2020M1:2021M12

julia> # collect with matching wildcard
julia> readfame("data.db", "c?", collect="c")   
Workspace with 1-variables
  c ⇒ Workspace with 3-variables

julia> # nested collect - matches the original structure of nested Workspaces
julia> readfame("data.db", collect=["c"=>["n"], "s"])  
Workspace with 4-variables
  a ⇒ 1.0
  b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2
  c ⇒ Workspace with 3-variables
  s ⇒ Workspace with 2-variables

julia> readfame("\"/home/usr/my data directory/data.db\"", "a", "b")   
Workspace with 2-variables
  a ⇒ 1.0
  b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2

```

"""
function readfame end
export readfame

# The workhorse - reads one FameObject and writes it into the 
function _readfame!(ret, ident, fo, db)
    try
        ret[ident] = unfame(do_read!(fo, db))
    catch e
        @info "Didn't load $(fo.name): $(sprint(showerror, e))"
    end
    return nothing
end

# If db is given as a string
@inline readfame(dbname, args...; kwargs...) =
    opendb(dbname) do db
        readfame(db, args...; kwargs...)
    end
# if list of names is not given
readfame(db::FameDatabase; kwargs...) = readfame(db, "?"; kwargs...)
# The other cases
function readfame(db::FameDatabase, args...; namecase=lowercase, prefix=nothing, collect=[], glue="_", kwargs...)
    if collect isa Union{AbstractString,Symbol,Pair{<:Union{AbstractString,Symbol},<:Any}}
        collect = [collect]
    end
    ret = Workspace()
    for wc in args
        fos = _iswildcard(wc) ? listdb(db, wc; kwargs...) : [quick_info(db, wc)]
        for fo in fos
            dest, name = _destination(ret, fo.name, glue, namecase, prefix, collect...)
            _readfame!(dest, Symbol(namecase(name)), fo, db)
        end
    end
    return ret
    ### experimental (write metadata for mvtseries, so we can load them as mvtseries)
    # return _ws_to_mvts(ret)
end

### experimental (write metadata for mvtseries, so we can load them as mvtseries)
# _ws_to_mvts(any) = any
# function _ws_to_mvts(w::Workspace)
#     names = get(w, :mvtseries_colnames, nothing)
#     if names === nothing
#         for (k,v) in w
#             w[k] = _ws_to_mvts(v)
#         end
#         return w
#     end
#     names = Symbol.(split(names, ','))
#     return MVTSeries(rangeof(w[names]); pairs(w[names])...)
# end

_iswildcard(wc) = occursin('?', wc) || occursin('^', wc)

_remove_prefix(name, pref) = startswith(name, pref) ? replace(name, pref => ""; count=1) : name
# Handle the prefix argument
_destination(ret, name, glue, namecase, prefix::AbstractString, args...) = _destination(ret, _remove_prefix(name, uppercase(string(prefix) * glue)), glue, namecase, nothing, args...)
# Recursion on the collect arguments
_destination(ret, name, glue, namecase, ::Nothing) = (ret, name)
_destination(ret, name, glue, namecase, ::Nothing, W::Any, args...) = error("Invalid type of W: $(typeof(W))")
_destination(ret, name, glue, namecase, ::Nothing, W::Union{Symbol,AbstractString}, args...) = _destination(ret, name, glue, namecase, nothing, W => [], args...)
@inline function _destination(ret, name, glue, namecase, ::Nothing, (Wpref, Collect)::Pair{<:Union{Symbol,AbstractString},<:Any}, args...)
    parts = split(name, glue)
    if length(parts) > 1 && (Wpref == "?" || Wpref == "*")
        Wpref = namecase(parts[1])
    end
    pref = uppercase(string(Wpref) * glue)
    if startswith(name, pref)
        if Collect isa Union{Symbol,AbstractString}
            Collect = [Collect]
        end
        return _destination(get!(ret, Symbol(Wpref), Workspace()), join(parts[2:end], glue), glue, namecase, nothing, Collect...)
    else
        return _destination(ret, name, glue, namecase, nothing, args...)
    end
end



"""
    unfame(fo::FameObject)

Convert a `FameObject` to a Julia type.

* PRECISION SCALAR => `Float64`
* NUMERIC SCALAR => `Float32`
* STRING SCALAR => `String`
* BOOLEAN SCALAR => `Bool`
* NAMELIST => `String` (Formatted as "{NAME1,NAME2,ETC}", see Fame help for
  details.)
* DATE SCALAR => [`MIT`](@ref TimeSeriesEcon.MIT) (CASE becomes `MIT{Unit}`,
  Frequencies not supported by TimeSeriesEcon throw an `ErrorException`)
* PRECISION SERIES => [`TSeries`](@ref TimeSeriesEcon.TSeries)
* NUMERIC SERIES => [`TSeries`](@ref TimeSeriesEcon.TSeries) with element type
  `Float32`
* BOOLEAN SERIES => [`TSeries`](@ref TimeSeriesEcon.TSeries) with element type
  `Bool`
* DATE SERIES => [`TSeries`](@ref TimeSeriesEcon.TSeries) with element type
  [`MIT`](@ref TimeSeriesEcon.MIT)
* STRING SERIES => `Vector{String}` (the time series metadata is lost) 
"""
function unfame end
export unfame

unfame(fo::FameObject{:scalar,:precision}) = _unmissing!(fo.data, Val(:precision))[]
unfame(fo::FameObject{:scalar,:numeric}) = _unmissing!(fo.data, Val(:numeric))[]
unfame(fo::FameObject{:scalar,:string}) = fo.data[]
unfame(fo::FameObject{:scalar,:boolean}) = fo.data[] != 0
unfame(fo::FameObject{:scalar,:namelist}) = fo.data[]
unfame(fo::FameObject{:scalar,TY}) where {TY} = _date_to_mit(TY, fo.data[])

unfame(fo::FameObject{:series,:precision,FR}) where {FR} =
    TSeries(_date_to_mit(FR, fo.first_index[]), _unmissing!(fo.data, Val(:precision)))
unfame(fo::FameObject{:series,:numeric,FR}) where {FR} =
    TSeries(_date_to_mit(FR, fo.first_index[]), _unmissing!(fo.data, Val(:numeric)))
unfame(fo::FameObject{:series,:string,FR}) where {FR} =
    copy(fo.data) # error("Can't handle string series")
function unfame(fo::FameObject{:series,TY,FR}) where {TY,FR}
    if length(fo.data) == 1 && _ismissing(fo.data[1], Val(TY))
        TSeries(MIT{_freq_from_fame(TY)}, _date_to_mit(FR, fo.first_index[]))
    else
        return TSeries(_date_to_mit(FR, fo.first_index[]), [_date_to_mit(TY, d) for d in fo.data])
    end
end
function unfame(fo::FameObject{:series,:boolean,FR}) where {FR}
    if length(fo.data) == 1 && _ismissing(fo.data[1], Val(:boolean))
        return TSeries(Bool, _date_to_mit(FR, fo.first_index[]))
    else
        return TSeries(_date_to_mit(FR, fo.first_index[]), [d != 0 for d in fo.data])
    end
end
    


from_fame_quarterly_map = Dict(
    :january    => Quarterly{1},
    :february   => Quarterly{2},
    :march      => Quarterly{3},
    :april      => Quarterly{1},
    :may        => Quarterly{2},
    :june       => Quarterly{3},
    :july       => Quarterly{1},
    :august     => Quarterly{2},
    :september  => Quarterly{3},
    :october    => Quarterly{1},
    :november   => Quarterly{2},
    :december   => Quarterly{3}
)

from_fame_yearly_map = Dict(
    :january    => Yearly{1},
    :february   => Yearly{2},
    :march      => Yearly{3},
    :april      => Yearly{4},
    :may        => Yearly{5},
    :june       => Yearly{6},
    :july       => Yearly{7},
    :august     => Yearly{8},
    :september  => Yearly{9},
    :october    => Yearly{10},
    :november   => Yearly{11},
    :december   => Yearly{12}
)

from_fame_halfyearly_map = Dict(
    :january    => HalfYearly{1},
    :february   => HalfYearly{2},
    :march      => HalfYearly{3},
    :april      => HalfYearly{4},
    :may        => HalfYearly{5},
    :june       => HalfYearly{6},
    :july       => HalfYearly{1},
    :august     => HalfYearly{2},
    :september  => HalfYearly{3},
    :october    => HalfYearly{4},
    :november   => HalfYearly{5},
    :december   => HalfYearly{6}
)

from_fame_weekly_map = Dict(
    :monday     => Weekly{1},
    :tuesday    => Weekly{2},
    :wednesday  => Weekly{3},
    :thursday   => Weekly{4},
    :friday     => Weekly{5},
    :saturday   => Weekly{6},
    :sunday     => Weekly{7},
)

from_fame_frequencies_map = Dict(
    :quarterly  => from_fame_quarterly_map,
    :monthly    => Monthly,
    :annual     => from_fame_yearly_map,
    :semiannual => from_fame_halfyearly_map,
    :case       => Unit,
    :daily      => Daily,
    :business   => BDaily,
    :weekly     => from_fame_weekly_map
)

@inline _freq_from_fame(fr) =
    (
        fr = string(val_to_symbol(fr, fame_freq));
        fr_split = Symbol.(split(fr, "_"));
        # could maybe use more error checking
        fr_split[1] ∈ keys(from_fame_frequencies_map) && from_fame_frequencies_map[fr_split[1]] isa Dict ? from_fame_frequencies_map[fr_split[1]][fr_split[2]] :
        fr_split[1] ∈ keys(from_fame_frequencies_map) ? from_fame_frequencies_map[fr_split[1]] :
        error("Cannot convert FAME frequency $fr to TimeSeriesEcon.")
    )

function _date_to_mit(fr, date)
    F = _freq_from_fame(fr)
    F == Unit && return MIT{F}(date)
    y = Ref{Cint}()
    p = Ref{Cint}()
    if _ismissing(date, Val(fr))
        return typenan(MIT{F})
    end
    @fame_call_check(fame_index_to_year_period,
        (Cint, FameIndex, Ref{Cint}, Ref{Cint}),
        val_to_int(fr, fame_freq), date, y, p)
    if F <: Weekly
        return TimeSeriesEcon._weekly_from_yp(F, y[], p[])
    else
        return MIT{F}(y[], p[])
    end
end



to_fame_quarterly_map = Dict{Integer, Symbol}(
    1 => :quarterly_october,
    2 => :quarterly_november,
    3 => :quarterly_december
)
to_fame_yearly_map = Dict{Integer, Symbol}(
    1   => :annual_january,
    2   => :annual_february,
    3   => :annual_march,
    4   => :annual_april,
    5   => :annual_may,
    6   => :annual_june,
    7   => :annual_july,
    8   => :annual_august,
    9   => :annual_september,
    10  => :annual_october,
    11  => :annual_november,
    12  => :annual_december,
)
to_fame_halfyearly_map = Dict{Integer, Symbol}(
    1   => :semiannual_july,
    2   => :semiannual_august,
    3   => :semiannual_september,
    4   => :semiannual_october,
    5   => :semiannual_november,
    6   => :semiannual_december,
)
to_fame_weekly_map = Dict{Integer, Symbol}(
    1   => :weekly_monday,
    2   => :weekly_tuesday,
    3   => :weekly_wednesday,
    4   => :weekly_thursday,
    5   => :weekly_friday,
    6   => :weekly_saturday,
    7   => :weekly_sunday,
)
to_fame_frequencies_map = Dict{Type, Symbol}(
    Unit            => :case,
    Yearly          => :annual_december,
    HalfYearly      => :semiannual_december,
    Quarterly       => :quarterly_december,
    Monthly         => :monthly,
    Weekly          => :weekly_sunday,
    Daily           => :daily,
    BDaily          => :business,
)

function _freq_to_fame(F::Type{<:Quarterly{N}})  where N
    if N ∈ keys(to_fame_quarterly_map)
        return to_fame_quarterly_map[N]
    end
    return error("Cannot convert TimeSeriesEcon frequency $F to a FAME frequency.");
end
function _freq_to_fame(F::Type{<:HalfYearly{N}})  where N
    if N ∈ keys(to_fame_halfyearly_map)
        return to_fame_halfyearly_map[N]
    end
    return error("Cannot convert TimeSeriesEcon frequency $F to a FAME frequency.");
end
function _freq_to_fame(F::Type{<:Yearly{N}})  where N
    if N ∈ keys(to_fame_yearly_map)
        return to_fame_yearly_map[N]
    end
    return error("Cannot convert TimeSeriesEcon frequency $F to a FAME frequency.");
end
function _freq_to_fame(F::Type{<:Weekly{N}})  where N
    if N ∈ keys(to_fame_weekly_map)
        return to_fame_weekly_map[N]
    end
    return error("Cannot convert TimeSeriesEcon frequency $F to a FAME frequency.");
end
@inline _freq_to_fame(F) =
    (
        F ∈ keys(to_fame_frequencies_map) && return to_fame_frequencies_map[F];
        return error("Cannot convert TimeSeriesEcon frequency $F to a FAME frequency.");
    )

function _mit_to_date(x::MIT{F}) where {F<:Frequency}
    F == Unit && return (:case, FameIndex(Int(x)))
    fr = _freq_to_fame(F)
    if istypenan(x)
        return (fr, FAME_INDEX_NC)
    end
    if F <: Weekly
        yr, p = TimeSeriesEcon._mit2yp(x)
    else
        yr, p = mit2yp(x)
    end
    index = Ref{FameIndex}(-1)
    @fame_call_check(fame_year_period_to_index,
        (Cint, Ref{FameIndex}, Cint, Cint),
        val_to_int(fr, fame_freq), index, yr, p)
    return (fr, index[])
end

"""
    writefame(db, data; options)

Write Julia data to a FAME database.

### Arguments:
* `db` can be a string containing the path to a FAME .db file or an instance of
  [`FameDatabase`](@ref).
* `data` is a collection of data which will be written to the database.
  - If `data` is an `MVTSeries`, each series will be written to the database.
  - If `data` is a `Workspace`, each element will be written as a separate FAME
    object. In this case any nested `Workspace` of `MVTSeries` objects will be
    written recursively by prepending the names.

### Options:
* `mode::Symbol` - if `db` is a string, the database is opened with the
  given `mode`. The default is :overwrite.
* `prefix::Union{Nothing,String}` - the given `prefix` will be prepended to the
  name of each object written in the database. The default is `nothing`, i.e.
  nothing will be prepended. NOTE: `prefix=nothing` and `prefix=""` are not the
  same.
* `glue::String` - the `glue` is used to join the prefix to the name. The
  default is `"_"`.

### Examples:
```
julia> w = Workspace(; a=1, b=TSeries(2020Q1,ones(10)), s=MVTSeries(2020M1, collect("ab"), randn(24,2)))
Workspace with 2-variables
  a ⇒ 1.0
  b ⇒ 10-element TSeries{Quarterly} with range 2020Q1:2022Q2
  s ⇒ 24×2 MVTSeries{Monthly} with range 2020M1:2021M12 and variables …

julia> writefame("w.db", w)

julia> listdb("w.db")
2-element Vector{FAME.FameObject}:
 A: scalar,precision,undefined,0:0,0:0
 B: series,precision,quarterly_december,2020:1,2022:2
 S_A: series,precision,monthly,2020:1,2021:12
 S_B: series,precision,monthly,2020:1,2021:12

```
"""
function writefame end
export writefame

# The workhorse - write an iterable of (name, value) pairs
function _writefame(db, iterable, prefix, glue)
    for (name, value) in iterable
        if prefix !== nothing
            name = Symbol(prefix, glue, name)
        end
        _writefame_one(db, value, name, glue)
    end
end

function _writefame_one(db, value::Workspace, name, glue)
    _writefame(db, pairs(value), name, glue)
    return
end

function _writefame_one(db, value::MVTSeries, name, glue)
    _writefame(db, pairs(value), name, glue)
    ### experimental (write metadata for mvtseries, so we can load them as mvtseries)
    # nms = join(colnames(value), ",")
    # _writefame(db, [(:mvtseries_colnames => nms),], name, glue)
    return
end

function _writefame_one(db, value, name, glue)
    try
        fo = refame(name, value)
        do_write(fo, db)
    catch e
        @info "Failed to write $(name): $(sprint(showerror, e))" e
    end
    return
end

# If database is given as a string
@inline writefame(dbname::AbstractString, data...; mode=:overwrite, kwargs...) =
    opendb(dbname, mode) do db
        writefame(db, data...; kwargs...)
    end

const _FameWritable = Union{MVTSeries,Workspace}

# # write a single Workspace or MVTSeries
# @inline writefame(db::FameDatabase, data::_FameWritable; prefix=nothing, glue="_") = 
#     _writefame(db, pairs(data), prefix, glue)

# write a list of MVTSeries and Workspace
writefame(db::FameDatabase, data::_FameWritable...; kwargs...) = writefame(db, data; kwargs...)
@inline function writefame(db::FameDatabase, data::Tuple{_FameWritable,Vararg{_FameWritable}}; prefix=nothing, glue="_")
    for value in data
        _writefame_one(db, value, prefix, glue)
    end
end

"""
    refame(name, value)

Convert the given value to a [`FameObject`](@ref)

* `Real` => NUMERIC SCALAR (includes integers)
* `Float64` => PRECISION SCALAR
* `Bool` => BOOLEAN SCALAR
* [`MIT`](@ref TimeSeriesEcon.MIT) => DATE SCALAR
* `String` => NAMELIST, if it is in the form "{name1,name2,...}", otherwise
  STRING SCALAR
* `Vector{String}` => CASE SERIES of STRING
* [`TSeries`](@ref TimeSeriesEcon.TSeries) => a SERIES of the same frequency and
  type. The type conversions are the same as for scalars.
"""
function refame end
export refame

@inline refame(name::Symbol, value::T) where {T<:Real} = refame(name, convert(promote_type(T, Float32), value))

@inline function refame(name::Symbol, value::Float64)
    if value == typenan(value)
        value = FAME.FPRCNC
    end
    return FameObject{:scalar,:precision,:undefined,Ref{Float64}}(
        string(name), Ref(0), Ref(0), Ref(Float64(value)))
end

@inline function refame(name::Symbol, value::Float32)
    if value == typenan(value)
        value = FAME.FNUMNC
    end
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
    (fr, find) = _mit_to_date(firstdate(value))
    ElType = eltype(value)
    if ElType == Float32
        ty = :numeric
        val = Float32[istypenan(v) ? FNUMNC : v for v in value.values]
    elseif ElType == Float64
        ty = :precision
        val = Float64[istypenan(v) ? FPRCNC : v for v in value.values]
    elseif ElType <: MIT
        ty = _freq_to_fame(frequencyof(ElType))
        val = FameIndex[_mit_to_date(x)[2] for x in value.values]
    elseif ElType == Bool
        ty = :boolean
        val = Int32[x for x in value.values]
    else
        ty = :precision
        val = map(value.values) do v
            v = convert(Float64, v)
            istypenan(v) ? FPRCNC : v
        end
    end
    # empty TSeries have a single NaN 
    if isempty(val)
        if ElType == Float32
            push!(val, FNUMNA)
        elseif ElType == Bool
            push!(val, FBOONA)
        elseif ElType <: MIT
            push!(val, FAME_INDEX_NA)
        else # default to float64
            push!(val, FPRCNA)
        end
    end
    lind = find + length(val) - 1
    return FameObject{:series,ty,fr,typeof(val)}(
        string(name), Ref(find), Ref(lind), val)
end

const HNMVAL = Int32(0) # Normal value; not missing or magic
const HNCVAL = Int32(1) # Missing NC - Not Computable
const HNAVAL = Int32(2) # Missing NA - Not Available
const HNDVAL = Int32(3) # Missing ND - Not Defined
const HMGVAL = Int32(4) # Magic value; for internal use only

function _ismissing(x, ::Val{:precision})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmispm, (Cdouble, Ref{Cint}), Float64(x), mt)
    return mt[] != HNMVAL
end

function _ismissing(x, ::Val{:numeric})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmisnm, (Cfloat, Ref{Cint}), Float32(x), mt)
    return mt[] != HNMVAL
end

function _ismissing(x, ::Val{:boolean})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmisbm, (Cint, Ref{Cint}), Int32(x), mt)
    return mt[] != HNMVAL
end

function _ismissing(x, ::Val{:string})
    mt = Ref{Int32}(-1)
    @cfm_call_check(cfmissm, (Cstring, Ref{Cint}), String(strip(x, '\0')), mt)
    return mt[] != HNMVAL
end

function _ismissing(x, ::Val{FR}) where {FR}
    mt = Ref{Int32}(-1)
    @fame_call_check(fame_date_missing_type, (Clonglong, Ref{Cint}), Int64(x), mt)
    return mt[] != HNMVAL
end

function _unmissing!(x::Ref, v::Val{T}) where {T}
    nan = typenan(eltype(x))
    if _ismissing(x[], v)
        x[] = nan
    end
    return x
end

function _unmissing!(x::Vector, v::Val{T}) where {T}
    # a single NaN value is an empty TSeries
    if length(x) == 1 && _ismissing(x[1], v)
        return empty!(x)
    end
    nan = typenan(eltype(x))
    for i = eachindex(x)
        if _ismissing(x[i], v)
            x[i] = nan
        end
    end
    return x
end


