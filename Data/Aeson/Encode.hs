{-# LANGUAGE CPP, BangPatterns, OverloadedStrings #-}

-- |
-- Module:      Data.Aeson.Encode
-- Copyright:   (c) 2012 Bryan O'Sullivan
--              (c) 2011 MailRank, Inc.
-- License:     Apache
-- Maintainer:  Bryan O'Sullivan <bos@serpentine.com>
-- Stability:   experimental
-- Portability: portable
--
-- Efficiently serialize a JSON value.
--
-- Most frequently, you'll probably want to encode straight to UTF-8
-- (the standard JSON encoding) using 'encode'.
--
-- You can use the conversions to 'Builder's when embedding JSON messages as
-- parts of a protocol.
module Data.Aeson.Encode
    ( encode

#if MIN_VERSION_bytestring(0,10,4)
    -- * Encoding to Builders
    , encodeToByteStringBuilder
    , encodeToTextBuilder
#else
    -- * Encoding to Text Builders
    , encodeToTextBuilder
#endif

    -- * Deprecated
    , fromValue
    ) where

import Data.Aeson.Types (Value(..))
import Data.Monoid (mappend)
import Data.Scientific (Scientific, coefficient, base10Exponent, scientificBuilder)
import Data.Text.Lazy.Builder
import Data.Text.Lazy.Builder.Int (decimal)
import Numeric (showHex)
import qualified Data.HashMap.Strict as H
import qualified Data.Text as T
import qualified Data.Vector as V

#if MIN_VERSION_bytestring(0,10,4)
import Data.Aeson.Encode.ByteString (encode, encodeToByteStringBuilder)
#else
import Data.Aeson.Types (ToJSON(toJSON))
import qualified Data.ByteString.Lazy    as BL
import qualified Data.Text.Lazy.Builder  as TLB
import qualified Data.Text.Lazy.Encoding as TLE

-- | Encode a JSON 'Value' as a UTF-8 encoded 'BL.ByteString'.
encode :: ToJSON a => a -> BL.ByteString
encode = TLE.encodeUtf8 . TLB.toLazyText . encodeToTextBuilder . toJSON
#endif

-- | Encode a JSON 'Value' to a 'Builder', which can be embedded efficiently
-- in a text-based protocol.
encodeToTextBuilder :: Value -> Builder
encodeToTextBuilder =
    go
  where
    go Null       = {-# SCC "go/Null" #-} "null"
    go (Bool b)   = {-# SCC "go/Bool" #-} if b then "true" else "false"
    go (Number s) = {-# SCC "go/Number" #-} fromScientific s
    go (String s) = {-# SCC "go/String" #-} string s
    go (Array v)
        | V.null v = {-# SCC "go/Array" #-} "[]"
        | otherwise = {-# SCC "go/Array" #-}
                      singleton '[' <>
                      go (V.unsafeHead v) <>
                      V.foldr f (singleton ']') (V.unsafeTail v)
      where f a z = singleton ',' <> go a <> z
    go (Object m) = {-# SCC "go/Object" #-}
        case H.toList m of
          (x:xs) -> singleton '{' <> one x <> foldr f (singleton '}') xs
          _      -> "{}"
      where f a z     = singleton ',' <> one a <> z
            one (k,v) = string k <> singleton ':' <> go v

{-# DEPRECATED fromValue "Use 'encodeToTextBuilder' instead" #-}
fromValue :: Value -> Builder
fromValue = encodeToTextBuilder

string :: T.Text -> Builder
string s = {-# SCC "string" #-} singleton '"' <> quote s <> singleton '"'
  where
    quote q = case T.uncons t of
                Nothing      -> fromText h
                Just (!c,t') -> fromText h <> escape c <> quote t'
        where (h,t) = {-# SCC "break" #-} T.break isEscape q
    isEscape c = c == '\"' ||
                 c == '\\' ||
                 c == '<'  ||
                 c == '>'  ||
                 c < '\x20'
    escape '\"' = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape '\r' = "\\r"
    escape '\t' = "\\t"

    -- The following prevents untrusted JSON strings containing </script> or -->
    -- from causing an XSS vulnerability:
    escape '<'  = "\\u003c"
    escape '>'  = "\\u003e"

    escape c
        | c < '\x20' = fromString $ "\\u" ++ replicate (4 - length h) '0' ++ h
        | otherwise  = singleton c
        where h = showHex (fromEnum c) ""

fromScientific :: Scientific -> Builder
fromScientific s
    | e < 0     = scientificBuilder s
    | otherwise = decimal (coefficient s * 10 ^ e)
  where
    e = base10Exponent s

(<>) :: Builder -> Builder -> Builder
(<>) = mappend
{-# INLINE (<>) #-}
infixr 6 <>
