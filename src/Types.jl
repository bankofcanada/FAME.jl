# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.


const _VT = NamedTuple{NAMES,NTuple{N,Int32}} where {NAMES,N}

throw_wrong_value(kind::AbstractString, val) = throw(ArgumentError("Invalid $kind $val"))

check_value(val, valid::_VT) = throw_wrong_value(Val(valid), val)
check_value(val::AbstractString, valid::_VT) = check_value(Symbol(lowercase(val)), valid)
check_value(val::Symbol, valid::_VT) = haskey(valid, val) ? val : throw_wrong_value(Val(valid), val)
check_value(val::Integer, valid::_VT) = val ∈ valid ? val : throw_wrong_value(Val(valid), val)

val_to_symbol(val, valid::_VT) = check_value(val, valid)
val_to_symbol(val::Integer, valid::_VT) = keys(valid)[indexin([check_value(val, valid)], [valid...])[1]]

val_to_int(val, valid::_VT) = valid[check_value(val, valid)]
val_to_int(val::Integer, valid::_VT) = check_value(val, valid)

const access_mode = (;
    readonly=Int32(1),
    create=Int32(2),
    overwrite=Int32(3),
    update=Int32(4),
    shared=Int32(5),
    write=Int32(6),
    direct_write=Int32(7)
)
throw_wrong_value(::Val{access_mode}, val) = throw_wrong_value("access mode", val)
check_mode(val) = check_value(val, access_mode)

# Chli and FameDatabase each depends on the other. 
# We need AbstractFameDatabase only to make that work.
abstract type AbstractFameDatabase end;

"""
    struct Chli ⋯ end

The internal state of FAME.jl. There is no reason for users to play with this.
"""
struct Chli{AFD<:AbstractFameDatabase}
    lib::Union{Nothing,Ptr{Nothing}}
    opendb::Vector{AFD}
    workdb::Ref{AFD}
    Chli{AFD}(lib, od=AFD[], wd=Ref{AFD}()) where {AFD} = new(lib, od, wd)
end

"""
    global chli

The internal state of FAME.jl. There is no reason for users to play with this.
"""
global chli = Chli{AbstractFameDatabase}(nothing)
@inline getsym(sym::Symbol) = chli.lib !== nothing ? Libdl.dlsym(chli.lib, sym) : error("FAME not initialized.")

function push_db(db::AbstractFameDatabase)
    global chli
    push!(chli.opendb, db)
    return db
end

export FameDatabase
"""
    mutable struct FameDatabase … end

Fame database. See also [`opendb`](@ref), [`closedb!`](@ref), [`postdb`](@ref),
[`listdb`](@ref).
"""
mutable struct FameDatabase <: AbstractFameDatabase
    key::Int32
    name::String
    mode::Symbol
    function FameDatabase(key::Integer, name::AbstractString="", mode=:readonly)
        push_db(new(key, name, val_to_symbol(mode, access_mode)))
    end
end

Base.isopen(db::FameDatabase) = db.key >= 0
Base.isequal(l::FameDatabase, r::FameDatabase) = l.key == r.key

function Base.show(io::IO, x::FameDatabase)
    if x.key >= 0
        print(io, "$(x.name): open in $(x.mode) mode")
    else
        print(io, "$(x.name): closed")
    end
end

const fame_class = (;
    # refer to hli.h for the values
    series=Int32(1),
    scalar=Int32(2),
    formula=Int32(3),
    glname=Int32(5),
    glformula=Int32(6)
)
throw_wrong_value(::Val{fame_class}, val) = throw_wrong_value("class", val)
check_class(val) = check_value(val, fame_class)

#/* FAME BASIS Attribute Settings  */
const fame_basis = (;
    undefined=Int32(0),
    daily=Int32(1),
    business=Int32(2)
)
throw_wrong_value(::Val{fame_basis}, val) = throw_wrong_value("basis", val)
check_basis(val) = check_value(val, fame_basis)

#/* FAME OBSERVED Attribute Settings  */
const fame_observed = (;
    undefined=Int32(0),
    beginning=Int32(1),
    ending=Int32(2),
    averaged=Int32(3),
    summed=Int32(4),
    annualized=Int32(5),
    formula=Int32(6),
    high=Int32(7),
    low=Int32(8)
)
throw_wrong_value(::Val{fame_observed}, val) = throw_wrong_value("observed", val)
check_observed(val) = check_value(val, fame_observed)

#/* Relation */
const fame_relation = (;
    before=Int32(1),
    after=Int32(2),
    contains=Int32(3)
)
throw_wrong_value(::Val{fame_relation}, val) = throw_wrong_value("relation", val)
check_relation(val) = check_value(val, fame_relation)

const fame_freq = (;
    undefined=Int32(0),               #define HUNDFX    0	/* Undefined			*/
    daily=Int32(8),                   #define HDAILY    8	/* DAILY			*/
    business=Int32(9),                #define HBUSNS    9	/* BUSINESS			*/
    weekly_sunday=Int32(16),          #define HWKSUN   16	/* WEEKLY (SUNDAY)		*/
    weekly_monday=Int32(17),          #define HWKMON   17	/* WEEKLY (MONDAY)		*/
    weekly_tuesday=Int32(18),         #define HWKTUE   18	/* WEEKLY (TUESDAY)		*/
    weekly_wednesday=Int32(19),       #define HWKWED   19	/* WEEKLY (WEDNESDAY)		*/
    weekly_thursday=Int32(20),        #define HWKTHU   20	/* WEEKLY (THURSDAY)		*/
    weekly_friday=Int32(21),          #define HWKFRI   21	/* WEEKLY (FRIDAY)		*/
    weekly_saturday=Int32(22),        #define HWKSAT   22	/* WEEKLY (SATURDAY)		*/
    tenday=Int32(32),                 #define HTENDA   32	/* TENDAY			*/
    biweekly_asunday=Int32(64),       #define HWASUN   64	/* BIWEEKLY (ASUNDAY)		*/
    biweekly_amonday=Int32(65),       #define HWAMON   65	/* BIWEEKLY (AMONDAY)		*/
    biweekly_atuesday=Int32(66),      #define HWATUE   66	/* BIWEEKLY (ATUESDAY		*/
    biweekly_awednesday=Int32(67),    #define HWAWED   67	/* BIWEEKLY (AWEDNESDAY)	*/
    biweekly_athursday=Int32(68),     #define HWATHU   68	/* BIWEEKLY (ATHURSDAY)		*/
    biweekly_afriday=Int32(69),       #define HWAFRI   69	/* BIWEEKLY (AFRIDAY)		*/
    biweekly_asaturday=Int32(70),     #define HWASAT   70	/* BIWEEKLY (ASATURDAY)		*/
    biweekly_bsunday=Int32(71),       #define HWBSUN   71	/* BIWEEKLY (BSUNDAY)		*/
    biweekly_bmonday=Int32(72),       #define HWBMON   72	/* BIWEEKLY (BMONDAY)		*/
    biweekly_btuesday=Int32(73),      #define HWBTUE   73	/* BIWEEKLY (BTUESDAY)		*/
    biweekly_bwednesday=Int32(74),    #define HWBWED   74	/* BIWEEKLY (BWEDNESDAY)	*/
    biweekly_bthursday=Int32(75),     #define HWBTHU   75	/* BIWEEKLY (BTHURSDAY)		*/
    biweekly_bfriday=Int32(76),       #define HWBFRI   76	/* BIWEEKLY (BFRIDAY)		*/
    biweekly_bsaturday=Int32(77),     #define HWBSAT   77	/* BIWEEKLY (BSATURDAY)		*/
    twicemonthly=Int32(128),          #define HTWICM  128	/* TWICEMONTHLY			*/
    monthly=Int32(129),               #define HMONTH  129	/* MONTHLY			*/
    bimonthly_november=Int32(144),    #define HBMNOV  144	/* BIMONTHLY (NOVEMBER)		*/
    bimonthly_december=Int32(145),    #define HBIMON  145	/* BIMONTHLY (DECEMBER)		*/
    quarterly_october=Int32(160),     #define HQTOCT  160	/* QUARTERLY (OCTOBER)		*/
    quarterly_november=Int32(161),    #define HQTNOV  161	/* QUARTERLY (NOVEMBER)		*/
    quarterly_december=Int32(162),    #define HQTDEC  162	/* QUARTERLY (DECEMBER)		*/
    annual_january=Int32(192),        #define HANJAN  192	/* ANNUAL (JANUARY)		*/
    annual_february=Int32(193),       #define HANFEB  193	/* ANNUAL (FEBRUARY)		*/
    annual_march=Int32(194),          #define HANMAR  194	/* ANNUAL (MARCH)		*/
    annual_april=Int32(195),          #define HANAPR  195	/* ANNUAL (APRIL)		*/
    annual_may=Int32(196),            #define HANMAY  196	/* ANNUAL (MAY)			*/
    annual_june=Int32(197),           #define HANJUN  197	/* ANNUAL (JUNE)		*/
    annual_july=Int32(198),           #define HANJUL  198	/* ANNUAL (JULY)		*/
    annual_august=Int32(199),         #define HANAUG  199	/* ANNUAL (AUGUST)		*/
    annual_september=Int32(200),      #define HANSEP  200	/* ANNUAL (SEPTEMBER)		*/
    annual_october=Int32(201),        #define HANOCT  201	/* ANNUAL (OCTOBER)		*/
    annual_november=Int32(202),       #define HANNOV  202	/* ANNUAL (NOVEMBER)		*/
    annual_december=Int32(203),       #define HANDEC  203	/* ANNUAL (DECEMBER)		*/
    semiannual_july=Int32(204),       #define HSMJUL  204	/* SEMIANNUAL (JULY)		*/
    semiannual_august=Int32(205),     #define HSMAUG  205	/* SEMIANNUAL (AUGUST)		*/
    semiannual_september=Int32(206),  #define HSMSEP  206	/* SEMIANNUAL (SEPTEMBER)	*/
    semiannual_october=Int32(207),    #define HSMOCT  207	/* SEMIANNUAL (OCTOBER)		*/
    semiannual_november=Int32(208),   #define HSMNOV  208	/* SEMIANNUAL (NOVEMBER)	*/
    semiannual_december=Int32(209),   #define HSMDEC  209	/* SEMIANNUAL (DECEMBER)	*/
    ypp=Int32(224),                   #define HAYPP   224	/* YPP				*/
    ppy=Int32(225),                   #define HAPPY   225	/* PPY				*/
    secondly=Int32(226),              #define HSEC    226	/* SECONDLY			*/
    minutely=Int32(227),              #define HMIN    227	/* MINUTELY			*/
    hourly=Int32(228),                #define HHOUR   228	/* HOURLY			*/
    millisecondly=Int32(229),         #define HMSEC   229	/* MILLISECONDLY		*/
    case=Int32(232),                  #define HCASEX  232	/* CASE				*/
    weekly_pattern=Int32(233)        #define HWEEK_PATTERN 233 /* generic weekly pattern     */
)
throw_wrong_value(::Val{fame_freq}, val) = throw_wrong_value("frequency", val)
check_freq(val) = check_value(val, fame_freq)

iscase(x::Symbol) = x === :case
iscase(x::Integer) = x === fame_freq.case

const fame_type = (;
    undefined=Int32(0),   #define HUNDFT    0	/* Undefined	*/
    numeric=Int32(1),     #define HNUMRC    1	/* NUMERIC	*/
    namelist=Int32(2),    #define HNAMEL    2	/* NAMELIST	*/
    boolean=Int32(3),     #define HBOOLN    3	/* BOOLEAN	*/
    string=Int32(4),      #define HSTRNG    4	/* STRING	*/
    precision=Int32(5),   #define HPRECN    5	/* PRECISION	*/
    date=Int32(6)        #define HDATE     6	/* General DATE	*/
)
throw_wrong_value(::Val{fame_type}, val) = throw_wrong_value("type", val)
check_type(val) = check_value(val, fame_type)

"""
    FameIndex

Integer 64-bit type that represents the internal index FAME uses to access
elements of series.
"""
const FameIndex = Int64

"""
    FameDate

64-bit integer type that FAME uses to encode dates of different frequencies.
"""
const FameDate = FameIndex

## More types are defined in FameObjects. We need stuff from ChliLibrary.jl in
## order to define those, so we can't include them here.

