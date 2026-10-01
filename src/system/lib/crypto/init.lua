local sha = ISO.require("system/lib/crypto/sha.lua")
local encoding = ISO.require("system/lib/crypto/encoding.lua")
local ecc = ISO.require("system/lib/crypto/secp256k1.lua")
local chacha = ISO.require("system/lib/crypto/chacha20.lua")
local bignum = ISO.require("system/lib/crypto/bignum.lua")
local random = ISO.require("system/lib/crypto/random.lua")
local M = {}

local function pad32(s)
  if #s >= 32 then return s:sub(-32) end
  return string.rep("\0", 32 - #s) .. s
end

function M.sha256(data, binary)
  local hex, bin = sha.sha256(data or "")
  return binary and bin or hex
end

function M.hmac(key, data, binary)
  return sha.hmac_sha256(key, data, binary)
end

function M.hkdf(ikm, salt, info, len)
  return encoding.hkdf(ikm, salt, info or "CCLUA-LINUX", len or 32)
end

function M.random(count)
  return random.bytes(count)
end

function M.keypair()
  local lastErr
  for attempt=1,8 do
    local private=ecc.generatePrivateKey()
    local ok,public=pcall(ecc.getPublicKey,private)
    if ok and public and public.x and public.y then
      return {
        private=private:toString(),
        public={x=public.x:toString(),y=public.y:toString()},
      }
    end
    lastErr=public
    if random.absorb then random.absorb("keypair-retry:"..attempt..":"..tostring(lastErr)) end
  end
  error("ECC key generation failed after retries: "..tostring(lastErr),2)
end
local function pubObject(public)
  return {x=bignum(tostring(public.x)),y=bignum(tostring(public.y))}
end
local function privObject(private)
  return bignum(tostring(private))
end

function M.publicFingerprint(public)
  local serial=tostring(public.x)..":"..tostring(public.y)
  local hex=M.sha256(serial,false)
  local parts={}
  for i=1,#hex,4 do parts[#parts+1]=hex:sub(i,i+3) end
  return "SHA256:"..table.concat(parts,":")
end

function M.sharedSecret(private,public)
  local shared=ecc.getSharedSecret(privObject(private),pubObject(public))
  if not shared then return nil,"invalid public key" end
  return pad32(shared:toBytes())
end

function M.sign(private,message)
  local sig=ecc.sign(privObject(private),message)
  return {r=sig.r:toString(),s=sig.s:toString()}
end

function M.verify(public,message,signature)
  local result=ecc.verify(pubObject(public),message,{
    r=bignum(tostring(signature.r)),s=bignum(tostring(signature.s))
  })
  return result and result.result or false
end

function M.deriveSession(shared,clientNonce,serverNonce,context)
  local salt=(clientNonce or "")..(serverNonce or "")
  return M.hkdf(shared,salt,"CCLUA-SECURE/"..tostring(context or "session"),64)
end

function M.seal(key,nonce,plaintext,aad)
  local cipher,tag=chacha.aead_encrypt(plaintext,key,nonce,aad or "")
  return {cipher=encoding.toBase64(cipher),tag=encoding.toBase64(tag),nonce=encoding.toBase64(nonce)}
end

function M.open(key,packet,aad)
  local cipher=assert(encoding.fromBase64(packet.cipher))
  local tag=assert(encoding.fromBase64(packet.tag))
  local nonce=assert(encoding.fromBase64(packet.nonce))
  return chacha.aead_decrypt(cipher,key,nonce,tag,aad or "")
end

M.encoding=encoding
return M
