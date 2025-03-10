{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Test suite.

module Posix (spec) where

import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import Test.Hspec

import Common.Posix (parseFails, parseSucceeds, parserTest)
import qualified Common.Posix
import Path.Posix
import Path.Internal.Posix
import TH.Posix ()

-- | Test suite (Posix version).
spec :: Spec
spec =
  do describe "Parsing: Path Abs Dir" parseAbsDirSpec
     describe "Parsing: Path Rel Dir" parseRelDirSpec
     describe "Parsing: Path Abs File" parseAbsFileSpec
     describe "Parsing: Path Rel File" parseRelFileSpec
     Common.Posix.spec
     describe "Restrictions" restrictions
     describe "Aeson Instances" aesonInstances
     describe "QuasiQuotes" quasiquotes

-- | Restricting the input of any tricks.
restrictions :: Spec
restrictions =
  do -- These ~ related ones below are now lifted:
     -- https://github.com/chrisdone/path/issues/19
     parseSucceeds "~/" (Path "~/")
     parseSucceeds "~/foo" (Path "~/foo/")
     parseSucceeds "~/foo/bar" (Path "~/foo/bar/")
     parseSucceeds "a.." (Path "a../")
     parseSucceeds "..a" (Path "..a/")
     --
     parseFails "../"
     parseFails ".."
     parseFails "/.."
     parseFails "/foo/../bar/"
     parseFails "/foo/bar/.."

-- | Tests for the tokenizer.
parseAbsDirSpec :: Spec
parseAbsDirSpec =
  do failing ""
     failing "./"
     failing "foo.txt"
     succeeding "/" (Path "/")
     succeeding "//" (Path "/")
     succeeding "///foo//bar//mu/" (Path "/foo/bar/mu/")
     succeeding "///foo//bar////mu" (Path "/foo/bar/mu/")
     succeeding "///foo//bar/.//mu" (Path "/foo/bar/mu/")

  where failing x = parserTest parseAbsDir x Nothing
        succeeding x with = parserTest parseAbsDir x (Just with)

-- | Tests for the tokenizer.
parseRelDirSpec :: Spec
parseRelDirSpec =
  do failing ""
     failing "/"
     failing "//"
     succeeding "~/" (Path "~/") -- https://github.com/chrisdone/path/issues/19
     failing "/"
     succeeding "./" (Path "")
     succeeding "././" (Path "")
     failing "//"
     failing "///foo//bar//mu/"
     failing "///foo//bar////mu"
     failing "///foo//bar/.//mu"
     succeeding "..." (Path ".../")
     succeeding "foo.bak" (Path "foo.bak/")
     succeeding "./foo" (Path "foo/")
     succeeding "././foo" (Path "foo/")
     succeeding "./foo/./bar" (Path "foo/bar/")
     succeeding "foo//bar//mu//" (Path "foo/bar/mu/")
     succeeding "foo//bar////mu" (Path "foo/bar/mu/")
     succeeding "foo//bar/.//mu" (Path "foo/bar/mu/")

  where failing x = parserTest parseRelDir x Nothing
        succeeding x with = parserTest parseRelDir x (Just with)

-- | Tests for the tokenizer.
parseAbsFileSpec :: Spec
parseAbsFileSpec =
  do failing ""
     failing "./"
     failing "/."
     failing "/foo/bar/."
     failing "~/"
     failing "./foo.txt"
     failing "/"
     failing "//"
     failing "///foo//bar//mu/"
     succeeding "/..." (Path "/...")
     succeeding "/foo.txt" (Path "/foo.txt")
     succeeding "///foo//bar////mu.txt" (Path "/foo/bar/mu.txt")
     succeeding "///foo//bar/.//mu.txt" (Path "/foo/bar/mu.txt")

  where failing x = parserTest parseAbsFile x Nothing
        succeeding x with = parserTest parseAbsFile x (Just with)

-- | Tests for the tokenizer.
parseRelFileSpec :: Spec
parseRelFileSpec =
  do failing ""
     failing "/"
     failing "//"
     failing "~/"
     failing "/"
     failing "./"
     failing "a/."
     failing "a/../b"
     failing "a/.."
     failing "../foo.txt"
     failing "//"
     failing "///foo//bar//mu/"
     failing "///foo//bar////mu"
     failing "///foo//bar/.//mu"
     succeeding "a.." (Path "a..")
     succeeding "..." (Path "...")
     succeeding "foo.txt" (Path "foo.txt")
     succeeding "./foo.txt" (Path "foo.txt")
     succeeding "././foo.txt" (Path "foo.txt")
     succeeding "./foo/./bar.txt" (Path "foo/bar.txt")
     succeeding "foo//bar//mu.txt" (Path "foo/bar/mu.txt")
     succeeding "foo//bar////mu.txt" (Path "foo/bar/mu.txt")
     succeeding "foo//bar/.//mu.txt" (Path "foo/bar/mu.txt")

  where failing x = parserTest parseRelFile x Nothing
        succeeding x with = parserTest parseRelFile x (Just with)

-- | Tests for the 'ToJSON' and 'FromJSON' instances
--
-- Can't use overloaded strings due to some weird issue with bytestring-0.9.2.1 / ghc-7.4.2:
-- https://travis-ci.org/sjakobi/path/jobs/138399072#L989
aesonInstances :: Spec
aesonInstances =
  do it "Decoding \"[\"/foo/bar\"]\" as a [Path Abs Dir] should succeed." $
       eitherDecode (LBS.pack "[\"/foo/bar\"]") `shouldBe` Right [Path "/foo/bar/" :: Path Abs Dir]
     it "Decoding \"[\"/foo/bar\"]\" as a [Path Rel Dir] should fail." $
       decode (LBS.pack "[\"/foo/bar\"]") `shouldBe` (Nothing :: Maybe [Path Rel Dir])
     it "Encoding \"[\"/foo/bar/mu.txt\"]\" should succeed." $
       encode [Path "/foo/bar/mu.txt" :: Path Abs File] `shouldBe` LBS.pack "[\"/foo/bar/mu.txt\"]"

-- | Test QuasiQuoters. Make sure they work the same as the $(mk*) constructors.
quasiquotes :: Spec
quasiquotes =
  do it "[absdir|/|] == $(mkAbsDir \"/\")"
       ([absdir|/|] `shouldBe` $(mkAbsDir "/"))
     it "[absdir|/home|] == $(mkAbsDir \"/home\")"
       ([absdir|/home|] `shouldBe` $(mkAbsDir "/home"))
     it "[reldir|foo|] == $(mkRelDir \"foo\")"
       ([reldir|foo|] `shouldBe` $(mkRelDir "foo"))
     it "[reldir|foo/bar|] == $(mkRelDir \"foo/bar\")"
       ([reldir|foo/bar|] `shouldBe` $(mkRelDir "foo/bar"))
     it "[absfile|/home/chris/foo.txt|] == $(mkAbsFile \"/home/chris/foo.txt\")"
       ([absfile|/home/chris/foo.txt|] `shouldBe` $(mkAbsFile "/home/chris/foo.txt"))
     it "[relfile|foo|] == $(mkRelFile \"foo\")"
       ([relfile|foo|] `shouldBe` $(mkRelFile "foo"))
     it "[relfile|chris/foo.txt|] == $(mkRelFile \"chris/foo.txt\")"
       ([relfile|chris/foo.txt|] `shouldBe` $(mkRelFile "chris/foo.txt"))
