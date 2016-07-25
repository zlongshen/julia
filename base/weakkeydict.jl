# weak key dictionaries

type WeakKeyDict{K,V} <: Associative{K,V}
    ht::Dict{Any,V}
    lock::Threads.RecursiveSpinLock
    finalizer::Function

    function WeakKeyDict()
        t = new(Dict{Any,V}(), Threads.RecursiveSpinLock(), identity)
        t.finalizer = function(k)
            # when a weak key is finalized, remove from dictionary if it is still there
            islocked(t) && return finalizer(k, t.finalizer)
            delete!(t, k)
        end
        return t
    end
end
WeakKeyDict() = WeakKeyDict{Any,Any}()

islocked(wkh::WeakKeyDict) = islocked(wkh.lock)
lock(f, wkh::WeakKeyDict) = lock(f, wkh.lock)
trylock(f, wkh::WeakKeyDict) = trylock(f, wkh.lock)

function setindex!{K}(wkh::WeakKeyDict{K}, v, key)
    k = convert(K, key)
    finalizer(k, wkh.finalizer)
    lock(wkh) do
        wkh.ht[WeakRef(k)] = v
    end
    return wkh
end

function getkey{K}(wkh::WeakKeyDict{K}, kk, default)
    return lock(wkh) do
        k = getkey(wkh.ht, kk, secret_table_token)
        is(k, secret_table_token) && return default
        return k.value::K
    end
end

get{K}(wkh::WeakKeyDict{K}, key, default) = lock(wkh) do; return get(wkh.ht, key, default); end
get{K}(default::Callable, wkh::WeakKeyDict{K}, key) = lock(wkh) do; return get(default, wkh.ht, key); end
get!{K}(wkh::WeakKeyDict{K}, key, default) = lock(wkh) do; return get!(wkh.ht, key, default); end
get!{K}(default::Callable, wkh::WeakKeyDict{K}, key) = lock(wkh) do; return get!(default, wkh.ht, key); end
pop!{K}(wkh::WeakKeyDict{K}, key) = lock(wkh) do; return pop!(wkh.ht, key); end
pop!{K}(wkh::WeakKeyDict{K}, key, default) = lock(wkh) do; return pop!(wkh.ht, key, default); end
delete!{K}(wkh::WeakKeyDict{K}, key) = lock(wkh) do; return delete!(wkh.ht, key); end
empty!(wkh::WeakKeyDict) = (lock(wkh) do; empty!(wkh.ht); end; wkh)
haskey{K}(wkh::WeakKeyDict{K}, key) = lock(wkh) do; return haskey(wkh.ht, key); end
getindex{K}(wkh::WeakKeyDict{K}, key) = lock(wkh) do; return getindex(wkh.ht, key); end
isempty(wkh::WeakKeyDict) = isempty(wkh.ht)
length(t::WeakKeyDict) = length(t.ht)

function start{K,V}(t::WeakKeyDict{K,V})
    gc_token = Ref{Bool}(false) # no keys will be deleted via finalizers until this token is gc'd
    finalizer(gc_token, function(r)
        if r[]
            r[] = false
            unlock(t.lock)
        end
    end)
    s = lock(t.lock)
    gc_token[] = true
    return (start(t.ht), gc_token)
end
done(t::WeakKeyDict, i) = done(t.ht, i[1])
function next{K,V}(t::WeakKeyDict{K,V}, i)
    gc_token = i[2]
    wkv, i = next(t.ht, i[1])
    kv = Pair{K,V}(wkv[1].value::K, wkv[2])
    return (kv, (i, gc_token))
end

function filter!(f, d::Union{ObjectIdDict,Dict,WeakKeyDict})
    for (k,v) in d
        if !f(k,v)
            delete!(d,k)
        end
    end
    return d
end
