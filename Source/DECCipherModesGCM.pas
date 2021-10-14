{*****************************************************************************
  The DEC team (see file NOTICE.txt) licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License. A copy of this licence is found in the root directory
  of this project in the file LICENCE.txt or alternatively at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
*****************************************************************************}
unit DECCipherModesGCM;

interface

{$INCLUDE DECOptions.inc}

uses
  {$IFDEF FPC}
  SysUtils;
  {$ELSE}
  System.SysUtils;
  {$ENDIF}

type
  /// <summary>
  ///   128 bit unsigned integer
  /// </summary>
  T128 = array[0..1] of UInt64;
  /// <summary>
  ///   pointer to an 128 bit unsigned integer
  /// </summary>
  P128 = ^T128;

  /// <summary>
  ///   A methopd of this type needs to be supplied for encrypting or decrypting
  ///   a block via this GCM algorithm. The method is implemented as a parameter,
  ///   to avoid the need to bring TGCM in the inheritance chain. TGCM thus can
  ///   be used for composition instead of inheritance.
  /// </summary>
  /// <param name="Source">
  ///   Data to be encrypted
  /// </param>
  /// <param name="Dest">
  ///   In this memory the encrypted result will be written
  /// </param>
  /// <param name="Size">
  ///   Size of source in byte
  /// </param>
  TEncodeDecodeMethod = procedure(Source, Dest: Pointer; Size: Integer) of Object;

  /// <summary>
  ///   Galois Counter Mode specific methods
  /// </summary>
  TGCM = class(TObject)
  private
     /// <summary>
     ///   Empty value?
     /// </summary>
     nullbytes : T128;
     /// <summary>
     ///   Table with precalculated values
     /// </summary>
     FM        : array[0..15,0..255] of T128;

     /// <summary>
     ///   Required for creating the table and encryption at least
     /// </summary>
     FH        : T128;
     /// <summary>
     ///   Calculated in initialization
     /// </summary>
     FY        : T128;
     /// <summary>
     ///   Calculated in initialization
     /// </summary>
     FE_K_Y0   : T128;

    /// <summary>
    ///   The data which shall be authenticated in parallel to the encryption
    /// </summary>
    FDataToAuthenticate      : TBytes;
    /// <summary>
    ///   Length of the authentication tag to generate in byte
    /// </summary>
    FAuthenticationTagLength : UInt32;
    /// <summary>
    ///   Generated authentication tag
    /// </summary>
    FAuthenticationTag        : TBytes;

    /// <summary>
    ///   Reference to the encode method of the actual cipher used
    /// </summary>
    FEncryptionMethod        : TEncodeDecodeMethod;
    /// <summary>
    ///   Reference to the decode method of the actual cipher used
    /// </summary>
    FDecryptionMethod        : TEncodeDecodeMethod;
    /// <summary>
    ///   True, when EncodeGCM has been called, false when DecodeGCM has been
    ///   called, as the last step depends on whether it is encryption or decryption
    /// </summary>

    /// <summary>
    ///   XOR implementation for unsigned 128 bit numbers
    /// </summary>
    /// <param name="x">
    ///   First number to xor
    /// </param>
    /// <param name="y">
    ///   Second number to xor the first with
    /// </param>
    /// <returns>
    ///   x xor y
    /// </returns>
    function XOR_T128(const x, y: T128): T128; inline;
    /// <summary>
    ///   XOR implementation for a pointer and an unsigned 128 bit number
    /// </summary>
    /// <param name="x">
    ///   Pointer on a T128 typed number to xor with y
    /// </param>
    /// <param name="y">
    ///   Second number to xor the first with
    /// </param>
    /// <returns>
    ///   x xor y
    /// </returns>
    function XOR_PointerWithT128(const x: Pointer; y: T128 ): T128; inline;
    /// <summary>
    ///   XORs the bytes given in a byte array with a T128 number given
    /// </summary>
    /// <param name="x">
    ///   Bytes which shall be XORed with the T128 number
    /// </param>
    /// <param name="XIndex">
    ///   Starting index within x from which onwards to XOR
    /// </param>
    /// <param name="Count">
    ///   Number of bytes from x beginning at XIndex to XOR
    /// </param>
    /// <param name="y">
    ///   Value to XOR the bytes from y with. XOR is done bytewise for each
    ///   byte of y
    /// </param>
    /// <param name="Result">
    ///   Result of the XOR operation
    /// </param>
    procedure XOR_ArrayWithT128(const x: TBytes; XIndex, Count: UInt64; y: T128; var Result: TBytes); inline;

    /// <summary>
    ///   XORs all elements of the precalculated matrix with the value passed
    /// </summary>
    /// <param name="hx">
    ///   Value who's two parts shall be XORed with the two parts of the
    ///   matrix each.
    /// </param>
    /// <returns>
    ///   result of the XOR Operation
    /// </returns>
    function poly_mult_H(const hx: T128) : T128; inline;

{ TODO : Kl�ren durch Michael was das tut, dann Doku }
    procedure SetAuthenticationCipherLength(var x : T128; al, cl : UInt64); inline;

    /// <summary>
    ///   Calculates a table with precalculated values which speeds up
    ///   operations later. The initialized table is the FM field.
    /// </summary>
    /// <param name="H">
    ///   Start value for the precalculation
    /// </param>
    procedure GenerateTableM8Bit(const H: T128); //inline;
    /// <summary>
    ///   Performs a right shift of 1 of all bytes in an 128 bit variable
    /// </summary>
    /// <param name="rx">
    ///   Variable on which the right shift is being performed
    /// </param>
    procedure ShiftRight(var rx: T128); //inline;

    /// <summary>
    ///   Incremepts the last 4 bytes of the index 0 part
    /// </summary>
    /// <param name="Y">
    ///   Value to increment, this is the return value as well.
    /// </param>
    procedure INCR(var Y : T128);

    /// <summary>
    ///   Defines the length of the resulting authentication value in bit.
    /// </summary>
    /// <param name="Value">
    ///   Sets the length of Authenticaton_tag in bit, values as per specification
    ///   are: 128, 120, 112, 104, or 96 bit. For certain applications, they
    ///   may be 64 or 32 as well, but the use of these two tag lengths
    ///   constrains the length of the input data and the lifetime of the key.
    /// </param>
    procedure SetAuthenticationTagLength(const Value: UInt32);
    /// <summary>
    ///   Returns the length of the calculated authehtication value in bit
    /// </summary>
    /// <returns>
    ///   Length of the calculated authentication value in bit
    /// </returns>
    function GetAuthenticationTagBitLength: UInt32;

    /// <summary>
    ///   Calculates the hash value
    /// </summary>
    /// <param name="AuthenticatedData">
    ///   Specifys the data for which an authentication value shall be
    ///   calculated. It is allowed to be nil.
    /// </param>
    /// <param name="Ciphertext">
    ///   Encrypted data used in the calculation
    /// </param>
    /// <returns>
    ///   Calculated raw hash value which will later get returned as AuthenticatedTag
    /// </returns>
    function CalcGaloisHash(AuthenticatedData, Ciphertext: TBytes): T128;

    /// <summary>
    ///   Encrypts a T128 value using the encryption method specified on init
    /// </summary>
    /// <param name="Value">
    ///   Value to be encrypted
    /// </param>
    /// <returns>
    ///   Encrypted value
    /// </returns>
    function EncodeT128(Value: T128): T128;

    /// <summary>
    ///   Checks whether two TBytes values contain the same data
    /// </summary>
    /// <param name="a">
    ///   First value for the comparison
    /// </param>
    /// <param name="b">
    ///   Second value for the comparison
    /// </param>
    /// <returns>
    ///   true, if both contain exactly the same data
    /// </returns>
    function IsEqual(const a, b : TBytes ):Boolean;
  public
    /// <summary>
    ///   Should be called when starting encryption/decryption in order to
    ///   initialize internal tables etc.
    /// </summary>
    /// <param name="EncryptionMethod">
    ///   Encryption method of the cypher used
    /// </param>
    /// <param name="DecryptionMethod">
    ///   Dencryption method of the cypher used
    /// </param>
    /// <param name="InitVector">
    ///   Initialization vector
    /// </param>
    procedure Init(EncryptionMethod : TEncodeDecodeMethod;
                   DecryptionMethod : TEncodeDecodeMethod;
                   InitVector       : TBytes);
    /// <summary>
    ///   Encodes a block of data using the supplied cipher
    /// </summary>
    /// <param name="Source">
    ///   Plain text to encrypt
    /// </param>
    /// <param name="Dest">
    ///   Ciphertext after encryption
    /// </param>
    /// <param name="Size">
    ///   Number of bytes to encrypt
    /// </param>
    procedure EncodeGCM(Source,
                        Dest   : TBytes;
                        Size   : Integer);
    /// <summary>
    ///   Decodes a block of data using the supplied cipher
    /// </summary>
    /// <param name="Source">
    ///   Encrypted ciphertext to decrypt
    /// </param>
    /// <param name="Dest">
    ///   Plaintext after decryption
    /// </param>
    /// <param name="Size">
    ///   Number of bytes to decrypt
    /// </param>
    procedure DecodeGCM(Source,
                        Dest   : TBytes;
                        Size   : Integer);

    /// <summary>
    ///   The data which shall be authenticated in parallel to the encryption
    /// </summary>
    property DataToAuthenticate : TBytes
      read   FDataToAuthenticate
      write  FDataToAuthenticate;
    /// <summary>
    ///   Sets the length of AuthenticatonTag in bit, values as per official
    ///   specification are: 128, 120, 112, 104, or 96 bit. For certain
    ///   applications, they may be 64 or 32 as well, but the use of these two
    ///   tag lengths constrains the length of the input data and the lifetime
    ///   of the key.
    /// </summary>
    property AuthenticationTagBitLength : UInt32
      read   GetAuthenticationTagBitLength
      write  SetAuthenticationTagLength;
    /// <summary>
    ///   Calculated authentication value
    /// </summary>
    property AuthenticationTag : TBytes
      read   FAuthenticationTag
      write  FAuthenticationTag;
  end;

implementation

function TGCM.XOR_T128(const x, y : T128): T128;
begin
  Result[0] := x[0] xor y[0];
  Result[1] := x[1] xor y[1];
end;

function TGCM.XOR_PointerWithT128(const x : Pointer; y : T128): T128;
begin
  Result[0] := P128(x)^[0] xor y[0];
  Result[1] := P128(x)^[1] xor y[1];
end;

procedure TGCM.XOR_ArrayWithT128(const x: TBytes; XIndex, Count: UInt64; y: T128; var Result: TBytes);
var
  i  : integer;
  { TODO : change to a pointer to y[0], to get rid of the absolute? }
  by : array[0..15] of byte absolute y[0];
begin
  for i := 0 to Count-1 do
  begin
    Result[XIndex] := x[XIndex] xor by[i];
    inc(XIndex);
  end;
end;

function TGCM.poly_mult_H(const hx : T128): T128;
var
  i : integer;
  { TODO : change to a pointer to hx[0], to get rid of the absolute? }
  x : array[0..15] of byte absolute hx[0];
begin
  Result := FM[0, x[0]];

  for i := 1 to 15 do
  begin
    Result[0] := Result[0] xor FM[i, x[i]][0];
    Result[1] := Result[1] xor FM[i, x[i]][1];
  end;
end;

procedure TGCM.SetAuthenticationCipherLength(var x : T128; al, cl : UInt64);
var
  i  : integer;
  { TODO : change to a pointer to x[0], to get rid of the absolute? }
  hx : array[0..15] of byte absolute x[0];
begin
  // al:
  x := nullbytes;
  i := 7;

  repeat
    hx[i] := al mod 256;
    al := al shr 8;
    dec(i);
  until al = 0;

  // cl:
  i := 15;

  repeat
    hx[i] := cl mod 256;
    cl := cl shr 8;
    dec(i);
  until cl = 0;
end;

procedure TGCM.GenerateTableM8Bit(const H : T128);
var
  hbit, hbyte, i, j : integer;
  HP : T128;
  { TODO : change to a pointer to HP[0], to get rid of the absolute? }
  bHP : array[0..15] of byte absolute HP[0];
  mask : byte;
begin
  HP := H;
  for hbyte := 0 to 15 do
  begin
    mask := 128;
    for hbit := 0 to 7 do
    begin
      FM[hbyte, mask] := HP;

      if (bHP[15] and 1 = 0) then
        ShiftRight(HP)
      else
      begin
        ShiftRight(HP);
        bHP[0] := bHP[0] xor $e1;
      end;

      mask := mask shr 1;
    end;
  end;

  for hbyte := 0 to 15 do
  begin
    i := 2;

    while i <= 128 do
    begin
      for j := 1 to i-1 do
        FM[hbyte, i+j] := XOR_T128(FM[hbyte, i], FM[hbyte, j]);
      i := i*2;
    end;

    FM[hbyte, 0] := nullbytes;
  end;
end;

procedure TGCM.ShiftRight(var rx : T128);
var
  { TODO : change to a pointer to rx[0], to get rid of the absolute? }
  x : array[0..15] of byte absolute rx[0];
  i : integer;
begin
  for i := 15 downto 1 do
    x[i] := (x[i] shr 1) or ((x[i-1] and 1) shl 7);

  x[0] := x[0] shr 1;
end;

procedure TGCM.SetAuthenticationTagLength(const Value: UInt32);
begin
  FAuthenticationTagLength := Value shr 3;
  SetLength(FAuthenticationTag, FAuthenticationTagLength);
end;

procedure TGCM.INCR(var Y : T128);
var
  { TODO : change to a pointer to Y[0], to get rid of the absolute? }
  bY : array[0..15] of byte absolute Y[0];
begin
  {$IFOPT Q+}{$DEFINE RESTORE_OVERFLOWCHECKS}{$Q-}{$ENDIF}
  {$Q-}
  inc(bY[15]);
  if bY[15] = 0 then
  begin
    inc(bY[14]);

    if bY[14] = 0 then
    begin
      inc(bY[13]);

      if bY[13] = 0 then
        inc(bY[12]);
    end;
  end;
  {$IFDEF RESTORE_OVERFLOWCHECKS}{$Q+}{$ENDIF}
end;

procedure TGCM.Init(EncryptionMethod : TEncodeDecodeMethod;
                    DecryptionMethod : TEncodeDecodeMethod;
                    InitVector       : TBytes);
var
  b    : ^Byte;
  OldH : T128;
begin
  Assert(Assigned(EncryptionMethod), 'No encryption method specified');

  // Clear calculated authentication value
  if (Length(FAuthenticationTag) > 0) then
    FillChar(FAuthenticationTag[0], Length(FAuthenticationTag), #0);

  FEncryptionMethod := EncryptionMethod;
  FDecryptionMethod := DecryptionMethod;

  Nullbytes[0] := 0;
  Nullbytes[1] := 0;

  OldH := FH;
  EncryptionMethod(@Nullbytes[0], @FH[0], 16);

  // Only generate the table when not already generated
  if (OldH[0] <> FH[0]) or (OldH[1] <> FH[1]) then
    GenerateTableM8Bit(FH);

  if length(InitVector) = 12 then
  begin
     FY[1] := 0;
     Move(InitVector[0], FY[0], 12);
     b := @FY[0];
     inc(b, 15);
     b^ := 1;
  end
  else
     FY := CalcGaloisHash(nil, InitVector);

  FEncryptionMethod(@FY[0], @FE_K_Y0[0], 16);
end;

function TGCM.CalcGaloisHash(AuthenticatedData, Ciphertext : TBytes): T128;
var
  AuthCipherLength : T128;
  x : T128;
  n : Uint64;

  procedure encode(data : TBytes);
  var
    i, mod_d, div_d, len_d : UInt64;
    hdata : T128;
  begin
    len_d := length(data);
    if (len_d > 0) then
    begin
      n := 0;
      div_d := len_d div 16;
      if div_d > 0 then
      for i := 0 to div_d -1 do
      begin
        x := poly_mult_H(XOR_PointerWithT128(@data[n], x ));
        inc(n, 16);
      end;

      mod_d := len_d mod 16;
      if mod_d > 0 then
      begin
        hdata := nullbytes;
        Move(data[n], hdata[0], mod_d);
        x := poly_mult_H(XOR_T128(hdata, x));
      end;
    end;
  end;

begin
  x := nullbytes;
  encode(AuthenticatedData);
  encode(Ciphertext);
  SetAuthenticationCipherLength(AuthCipherLength, length(AuthenticatedData) shl 3, length(ciphertext) shl 3);

  Result := poly_mult_H(XOR_T128(AuthCipherLength, x));
end;

procedure TGCM.DecodeGCM(Source, Dest: TBytes; Size: Integer);
var
  i, j, BlockCount : Uint64;
  a_tag : T128;
begin
  i := 0;
  BlockCount := Size div 16;

  for j := 1 to BlockCount do
  begin
    INCR(FY);
    P128(@Dest[i])^ := XOR_PointerWithT128(@Source[i], EncodeT128(FY));
    inc(i, 16);
  end;

  if i < Size then
  begin
    INCR(FY);
    XOR_ArrayWithT128(Source, i, UInt64(Size)-i, EncodeT128(FY), Dest);
  end;

  a_tag := XOR_T128(CalcGaloisHash(DataToAuthenticate, Source), FE_K_Y0);

  Setlength(FAuthenticationTag, FAuthenticationTagLength);
  Move(a_tag[0], FAuthenticationTag[0], FAuthenticationTagLength);

//  Result := IsEqual(authenticaton_tag, ba_tag);

//  if not IsEqual(authenticaton_tag, ba_tag) then
//    SetLength(plaintext, 0); // NIST FAIL => pt=''
end;

procedure TGCM.EncodeGCM(Source, Dest: TBytes; Size: Integer);
var
  i, j, div_len_plain : UInt64;
  AuthTag : T128;
begin
  i := 0;
  div_len_plain := Size div 16;
  for j := 1 to div_len_plain do
  begin
    INCR(FY);

    P128(@Dest[i])^ := XOR_PointerWithT128(@Source[i], EncodeT128(FY));

    inc(i,16);
  end;

  if i < Size then
  begin
    INCR(FY);
    XOR_ArrayWithT128(Source, i, UInt64(Size)-i, EncodeT128(FY), Dest);
  end;

  AuthTag := XOR_T128(CalcGaloisHash(DataToAuthenticate, Dest), FE_K_Y0);
  Setlength(FAuthenticationTag, FAuthenticationTagLength);
  Move(AuthTag[0], FAuthenticationTag[0], FAuthenticationTagLength);
end;

function TGCM.IsEqual(const a, b : TBytes):Boolean;
begin
  if (length(a) <> length(b)) then
    Result := false
  else
    Result := CompareMem(@a[0], @b[0], length(a));
end;

function TGCM.EncodeT128(Value: T128): T128;
begin
  FEncryptionMethod(@Value[0], @Result[0], 16);
end;

function TGCM.GetAuthenticationTagBitLength: UInt32;
begin
  Result := FAuthenticationTagLength shl 3;
end;

//
//function decrypt( const key, IV : TBytes; out plaintext : TBytes; const authenticated_data,
//ciphertext : TBytes; len_auth_tag : integer; const authenticaton_tag : TBytes ) : boolean;
//var
//    i, j, div_len_ciph, len_ciph : Uint64;
//    a_tag, E_K_Y0, Y, H : T128;
//    bY : array[0..15] of byte absolute Y[0];
//    ba_Tag : TBytes;
//
//    function equal( const a, b : TBytes ):boolean;
//    begin
//      if length(a) <> length(b) then Result := false
//      else
//      Result := CompareMem( @a[0], @b[0], length(a) );
//    end;
//
//begin
//    len_auth_tag := len_auth_tag shr 3;
//
//    E_Init( key );
//    H := E_Cipher( nullbytes );
//    Table_M_8Bit(H);
//
//    len_ciph := length( ciphertext );
//    SetLength( plaintext, len_ciph );
//
//    if length(IV) = 12 then
//    begin
//       Y[1] := 0;
//       Move( IV[0], Y[0], 12 );
//       bY[15] := 1;
//    end
//    else
//       Y := CalcGaloisHash( H, nil, IV );
//
//    E_K_Y0 := E_Cipher( y );
//
//    i := 0;
//    div_len_ciph := len_ciph div 16;
//    for j := 1 to div_len_ciph do
//    begin
//      INCR( Y );
//      P128(@plaintext[i])^ := XOR_128_n( @ciphertext[i], E_cipher( Y ) );
//      inc(i,16);
//    end;
//
//    if i < len_ciph then
//    begin
//      INCR( Y );
//      XOR_128_n_l( ciphertext, i, len_ciph-i, E_cipher( Y ), plaintext );
//    end;
//
//    a_tag := XOR_128( CalcGaloisHash( H, authenticated_data, ciphertext ), E_K_Y0 );
//
//    Setlength( ba_tag, len_auth_tag );
//    Move( a_tag[0], ba_tag[0], len_auth_tag );
//
//    Result := equal( authenticaton_tag, ba_tag );
//    if not Result then SetLength( plaintext, 0 ); // NIST FAIL => pt=''
//end;
//

end.
