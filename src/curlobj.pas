(* **  Copyright (c) 2002-2005, Jeffrey Pohlmeyer, <yetanothergeek@yahoo.com>  ** *)
(* Licensed per the file COPYING, which should be included in all distributions *)

unit curlobj;

interface

{$H+}

uses
  AnsiStrings, // Ruzzz
  Classes, Sysutils, Windows, Winsock,
  Curl_h; // <- Core library

// <- Convenience functions for file-handling ( exist / access / size )

function FileIsReadable(const FN: string): Boolean;  // File exists and is readable.
function FileIsWriteable(const FN: string): Boolean; // File can be written and/or created.
function GetFileSize(const FN: string): LongInt;     // File size in bytes or -1 on error.

// Type declarations ( and Win32 MSVCRT ansi-c functions )

type
  PIOFile = Pointer;
  TThreadStartProc = procedure(Arg: Pointer); cdecl;

const
  MSVCRT_DLL = 'msvcrt.dll';

var
  DEFAULT_WIN32_CA_CERT: string = '';
  DEFAULT_WIN32_CA_PATH: string = '';

function Fopen(Path, Mode: PChar): PIOFile; cdecl; external MSVCRT_DLL name 'fopen';
function Fclose(F: PIOFile): LongInt; cdecl; external MSVCRT_DLL name 'fclose';
function Fread(Ptr: Pointer; Size: LongInt; Nmemb: LongInt; F: PIOFile): Size_t; cdecl;
  external MSVCRT_DLL name 'fread';
function Fwrite(const Ptr: Pointer; Size: LongInt; Nmemb: LongInt; F: PIOFile): Size_t; cdecl;
  external MSVCRT_DLL name 'fwrite';
function Fdopen(Fildes: LongInt; Mode: PChar): PIOFile; cdecl; external MSVCRT_DLL name '_fdopen';
function Malloc(N: LongInt): Pointer; cdecl; external MSVCRT_DLL name 'malloc';
procedure _free(P: Pointer); cdecl; external MSVCRT_DLL name 'free';
function _beginthread(Func: TThreadStartProc; Stack: DWORD; Arg: Pointer): DWORD; cdecl;
  external MSVCRT_DLL name '_beginthread';
procedure _endthread(); cdecl; external MSVCRT_DLL name '_endthread';
function Getenv(Varname: PChar): PChar; cdecl; external MSVCRT_DLL name 'getenv';

type
  TComponent = class(TObject) // lightweight "psuedo-component" for console apps
  private
    FOwner: TComponent;
    FTag: LongInt;
  public
    property Owner: TComponent read FOwner write FOwner;
    constructor Create(AOwner: TComponent);
  published
    property Tag: LongInt read FTag write FTag;
  end;

  TNotifyEvent = procedure(Obj: TObject) of object;

type
  TCurlProgressEvent = procedure(Sender: TObject; BytesTotal, BytesNow: Integer;
    var BContinue: Boolean) of object;
  TCurlHeaderEvent = procedure(Sender: TObject; Data: string; var BContinue: Boolean) of object;
  TCurlReceiveEvent = procedure(Sender: TObject; Data: PChar; Len: Cardinal; var BContinue: Boolean)
    of object;
  TCurlTransmitEvent = procedure(Sender: TObject; Data: PChar; var Len: Cardinal) of object;
  TCurlDebugEvent = procedure(Sender: TObject; Infotype: Curl_infotype; Data: PChar; Len: Cardinal;
    var BContinue: Boolean) of object;
  TCurlWaitCallback = procedure(UserData: Pointer); cdecl;
  TCurlListCookiesEvent = TCurlHeaderEvent;

  TCurlPostType = (POST_TYPE_PLAIN, POST_TYPE_ATTACHMENT, POST_TYPE_FILEDATA);
  CurlEncoding = (CURL_ENCODING_NONE, CURL_ENCODING_IDENTITY, CURL_ENCODING_DEFLATE);
  CurlCertType = (CURL_CERT_NONE, CURL_CERT_PEM, CURL_CERT_DER);
  CurlKeyType = (CURL_KEY_NONE, CURL_KEY_PEM, CURL_KEY_DER, CURL_KEY_ENG);
  CurlHostVerify = (CURL_VERIFY_NONE, CURL_VERIFY_EXIST, CURL_VERIFY_MATCH);
  CurlAuthenticationMethod = (AUTH_BASIC, AUTH_DIGEST, AUTH_GSSNEGOTIATE, AUTH_NTLM);
  CurlAuthenticationMethods = set of CurlAuthenticationMethod;
  CurlResolverVersion = LongInt;

  TCallbackType = (CBT_CALLBACK, CBT_EVENT, CBT_INTERNAL);
  TFileStreamType = (FST_STREAM, FST_FILENAME, FST_INTERNAL);

  TCallbackScheme = record
    Cb_type: TCallbackType;
    Fs_type: TFilestreamType;
    Stream: Pointer;
    Filename: PChar;
    Callback: Curl_write_callback;
    case Integer of
      0:
        (Hdr_event: TCurlHeaderEvent);
      1:
        (Rx_event: TCurlReceiveEvent);
      2:
        (Tx_event: TCurlTransmitEvent);
  end;

  TCurlFeatures = record
    Ipv6: Boolean;
    Kerberos4: Boolean;
    Ssl: Boolean;
    Libz: Boolean;
    Ntlm: Boolean;
    GssNegotiate: Boolean;
    Debug: Boolean;
    AsynchDns: Boolean;
    Spnego: Boolean;
    LargeFile: Boolean;
    Idn: Boolean;
    Sspi: Boolean;
  end;

  { "Helper" class to make the multipart/formdata stuff a little easier ... }
  TMultiPartFormData = class
  private
    FHttpPost: PCurl_HttpPost;
    FErrCODE: CurlCode;
    procedure DoAppend(var APost: PCurl_HttpPost; const PostInfo: Curl_HttpPost);
    procedure DoClear(var APost: PCurl_HttpPost);
  public
    property PostPtr: PCurl_HttpPost read FHttpPost;
    constructor Create;
    destructor Destroy; override;
    procedure Append(const PostInfo: Curl_HttpPost);
    procedure Add(const AName: string; const AContents: string; const AContentType: string;
      APostType: TCurlPostType);
    procedure Clear;
    property Result: CurlCODE read FErrCode;
  end;

  { A new class to provide a wrapper around the tcurl_slist structure ... }
  TCurlROList = class(TObject) // Read-only list
  private
    FList: Pcurl_slist;
    FCount: LongInt;
    FDirty: Boolean;
  protected
    function GetText: string;
    procedure SetText(const AStr: string);
    function GetItemPtr(N: LongInt): Pcurl_slist;
    function GetItems(N: LongInt): string;
    procedure SetItems(N: LongInt; const S: string);
    procedure Add(const AStr: string);
    procedure Delete(N: LongInt);
    procedure Clear;
  public
    constructor Create;
    destructor Destroy; override;
    property Text: string read GetText;
    property Items[index: Integer]: string read GetItems; default;
    property Count: LongInt read FCount;
  end;

  TCurlRWList = class(TCurlROList) // Read-Write list
  public
    procedure Add(const AStr: string);
    procedure Delete(N: LongInt);
    procedure Clear;
    property Text: string read GetText write SetText;
    property Items[index: Integer]: string read GetItems write SetItems; default;
  end;

  { Wrapper  around libcurl's cookie list }
  TCurlEnumCookiesFunction = function(Sender: TObject; const Cookie: Ansistring;
    UserData: Pointer): Boolean;
  TCurlStaleCookieState = set of (COOKIES_LIB_STALE, COOKIES_OBJ_STALE);

  TCurlCookieList = class(TObject)
  private
    FOwner: TObject;
    FHandle: PCurl;
    FList: Pcurl_slist;
    FState: TCurlStaleCookieState;
    function SendListToLib: CurlCode;
    function GetListFromLib: CurlCode;
    procedure RemoveDuplicates;
  public
    constructor Create(AOwner: TObject);
    destructor Destroy; override;
    function AddFromFile(const Filename: Ansistring): CurlCode;
    function SaveToFile(const Filename: Ansistring): CurlCode;
    function Add(const Cookie: Ansistring): Boolean;
    procedure ForEachCookie(Callback: TCurlEnumCookiesFunction; User_data: Pointer);
    procedure Clear;
  end;

type
  TCurlBase = class(TComponent) // Base class for TCurl and TCurlMulti
  private
    FBusy: Boolean;
    FThreaded: Boolean;
    FWaitInterval: LongInt;
    FOnWait: TNotifyEvent;
    FWaitCallback: TCurlWaitCallback;
    FWaitData: Pointer;
    FThread: DWORD;
  protected
    procedure SetWaitInterval(Ms: Longint);
    procedure SetOnWait(AEvent: TNotifyEvent);
    procedure SetWaitCallback(ACallback: TCurlWaitCallback);
  public
    constructor Create(AOwner: TComponent);
    property Busy: Boolean read FBusy;
    property WaitCallback: TCurlWaitCallback read FWaitCallback write SetWaitCallback;
    property WaitData: Pointer read FWaitData write FWaitData;
    property WaitInterval: LongInt read FWaitInterval write SetWaitInterval;
  published
    property OnWait: TNotifyEvent read FOnWait write SetOnWait;
    property Threaded: Boolean read FThreaded write FThreaded;
  end;

type
  TCurl = class(TCurlBase)
{$DEFINE TCURL_INTF}
  private
    FCurl: PCurl;          { The 'handle' to the curl session }
    FCurlResult: CurlCode; { Final return code from all calls to 'curl_easy' functions }

    FCrLf: Boolean;
    FVerbose: Boolean;
    FHeader: Boolean;
    FNoProgress: Boolean;
    FNoBody: Boolean;
    FFailOnError: Boolean;
    FUpload: Boolean;
    FPost: Boolean;
    FFtpListOnly: Boolean;
    FFtpAppend: Boolean;
    FNetrc: CURL_NETRC_OPTION;
    FFollowLocation: Boolean;
    FTransferText: Boolean;
    FPut: Boolean;
    FHttpProxyTunnel: Boolean;
    FSslVerifyPeer: Boolean;
    FFreshConnect: Boolean;
    FForbidReuse: Boolean;
    FHttpGet: Boolean;
    FFtpUseEpsv: Boolean;
    FFiletime: Boolean;
    FFtpAscii: Boolean;

    FAutoReferer: Boolean;

    FPort: Word;
    FTimeout: LongInt;
    FLowSpeedLimit: LongInt;
    FLowSpeedTime: LongInt;
    FResumeFrom: LongInt;
    FSslVersion: Curl_sslversion;
    FTimeCondition: Curl_TimeCond;
    FTimeValue: LongInt;
    FProxyPort: LongInt;
    FPostFieldSize: LongInt;
    FMaxRedirs: LongInt;
    FMaxConnects: LongInt;
    FConnectTimeout: LongInt;
    FBufferSize: LongInt;
    FDnsCacheTimeout: LongInt;
    FInfileSize: LongInt;
    FCookieSession: Boolean;
    FSslEngineDefault: Boolean;
    FDnsUseGlobalCache: Boolean;
    FNoSignal: Boolean;
    FUnrestrictedAuth: Boolean;
    FFtpUseEPRT: Boolean;

    FUrl: PChar;
    FProxy: PChar;
    FUserPwd: PChar;
    FProxyUserPwd: PChar;
    FRange: PChar;
    FPostFields: PChar;
    FReferer: PChar;
    FFtpPort: PChar;
    FUserAgent: PChar;
    FCookie: PChar;
    FSslCert: PChar;
    FSslCertPasswd: PChar;
    FCustomRequest: PChar;
    FInterface: PChar;
    FKrb4Level: PChar;
    FCaInfo: PChar;
    FRandomFile: PChar;
    FEgdSocket: PChar;
    FCookieJar: PChar;
    FCookieFile: PChar;
    FSslCipherList: PChar;
    FWriteInfo: PChar;
    FCaPath: PChar;
    FSslKey: PChar;
    FSslEngine: PChar;
    FSslKeyPassword: PChar;

    FHttpHdr: TCurlRWList;
    FQuote: TCurlRWList;
    FPostQuote: TCurlRWList;
    FPreQuote: TCurlRWList;
    FTelnetOptions: TCurlRWList;
    FHttp200Aliases: TCurlRWList;

    FFormData: TMultiPartFormData;
    FHttpPost: PCurl_HttpPost;

    FHttpVersion: Curl_http_version;
    FClosePolicy: Curl_closepolicy;
    FProxyType: Curl_proxytype;
    FEncoding: CurlEncoding;
    FSslCertType: CurlCertType;
    FSslKeyType: CurlKeyType;
    FSslVerifyHost: CurlHostVerify;

    FProgressFunction: Curl_progress_callback;
    FProgressData: Pointer;
    FOnProgress: TCurlProgressEvent;

    FDebugFunction: Curl_debug_callback;
    FDebugData: Pointer;
    FOnDebug: TCurlDebugEvent;

    FErrorBuffer: PChar;
    FErrorFile: PChar;
    FErrorStream: PIOFile;

    FHeaderScheme: TCallbackScheme;
    FReceiveScheme: TCallbackScheme;
    FTransmitScheme: TCallbackScheme;

    FPrivateData: Pointer;

    FHttpAuth: CurlAuthenticationMethods;
    FProxyAuth: CurlAuthenticationMethods;
    FFtpCreateMissingDirs: Boolean;
    FFtpResponseTimeout: LongInt;
    FIpResolve: CurlResolverVersion;
    FMaxFileSize: LongInt;
    FSslCtxData: Pointer;
    FSslCtxFunction: Curl_ssl_ctx_callback;

    FIoCtlCallback: Curl_ioctl_callback;
    FIoCtlData: Pointer;
    FCookieList: TCurlCookieList;
    FOnListCookies: TCurlListCookiesEvent;
    FSslEnginesList: TCurlROList;
    FTcpNoDelay: Boolean;
    FNetRcFile: PChar;
    FFtpAccount: PChar;

    FSourcePreQuote: TCurlRWList;
    FSourceQuote: TCurlRWList;
    FSourcePostQuote: TCurlRWList;

    FSourceUserPwd: PChar;
    FSourceUrl: PChar;
    FFtpSsl: Curl_ftpssl;
    FFtpAuth: Curl_ftpauth;
    FIgnoreContentLength: Boolean;

    FThdResult: CurlCode;
    FMultiNotifyDestroying: TNotifyEvent;
    FMulti: TObject;
    FPrev, FNext: TObject;

    FFtpSkipPasvIp: Boolean;

  protected

    procedure Release;
    procedure InitFields;
    function InitTransfer: CurlCode;
    procedure DoneTransfer(ACode: CurlCode);
    function DoPerform(ACurl: PCurl): CurlCode;
    procedure MutexLock;
    procedure MutexUnlock;

    procedure SetStringProp(var Field: PChar; const Value: string);
    procedure SetBoolOption(Option: CurlOption; out Field: Boolean; const Value: Boolean); overload;
    procedure SetIntOption(Option: CurlOption; out Field: Longint; const Value: Longint); overload;
    procedure SetStrOption(Option: CurlOption; var Field: PChar; const Value: string); overload;
    procedure SetPtrOption(Option: CurlOption; out Field: Pointer; const Value: Pointer); overload;

    procedure SetResultCode(ACode: CurlCode; AOption: CURLoption);

    procedure SetCrLf(const Value: Boolean);
    procedure SetVerbose(const Value: Boolean);
    procedure SetHeader(const Value: Boolean);
    procedure SetNoProgress(const Value: Boolean);
    procedure SetNoBody(const Value: Boolean);
    procedure SetFailOnError(const Value: Boolean);
    procedure SetUpload(const Value: Boolean);
    procedure SetPost(const Value: Boolean);
    procedure SetFtpListOnly(const Value: Boolean);
    procedure SetFtpAppend(const Value: Boolean);
    procedure SetNetrc(const Value: CURL_NETRC_OPTION);
    procedure SetFollowLocation(const Value: Boolean);
    procedure SetTransferText(const Value: Boolean);
    procedure SetPut(const Value: Boolean);
    procedure SetHttpProxyTunnel(const Value: Boolean);
    procedure SetSslVerifyPeer(const Value: Boolean);
    procedure SetFreshConnect(const Value: Boolean);
    procedure SetForbidReuse(const Value: Boolean);
    procedure SetHttpGet(const Value: Boolean);
    procedure SetFtpUseEpsv(const Value: Boolean);
    procedure SetFiletime(const Value: Boolean);

    procedure SetAutoReferer(const Value: Boolean);
    procedure SetPort(const Value: Word);
    procedure SetTimeout(const Value: LongInt);
    procedure SetLowSpeedLimit(const Value: LongInt);
    procedure SetLowSpeedTime(const Value: LongInt);
    procedure SetResumeFrom(const Value: LongInt);
    procedure SetSslVersion(const Value: Curl_sslversion);
    procedure SetTimeCondition(const Value: Curl_TimeCond);
    procedure SetTimeValue(const Value: LongInt);
    procedure SetProxyPort(const Value: LongInt);
    procedure SetPostFieldSize(const Value: LongInt);
    procedure SetMaxRedirs(const Value: LongInt);
    procedure SetMaxConnects(const Value: LongInt);
    procedure SetConnectTimeout(const Value: LongInt);
    procedure SetUrl(const Value: string);
    procedure SetProxy(const Value: string);
    procedure SetUserPwd(const Value: string);
    procedure SetProxyUserPwd(const Value: string);
    procedure SetRange(const Value: string);
    procedure SetPostFields(const Value: string);
    procedure SetReferer(const Value: string);
    procedure SetFtpPort(const Value: string);
    procedure SetUserAgent(const Value: string);
    procedure SetCookie(const Value: string);
    procedure SetSslCert(const Value: string);
    procedure SetSslCertPasswd(const Value: string);
    procedure SetCustomRequest(const Value: string);
    procedure SetInterface(const Value: string);
    procedure SetKrb4Level(const Value: string);
    procedure SetCaInfo(const Value: string);
    procedure SetRandomFile(const Value: string);
    procedure SetEgdSocket(const Value: string);
    procedure SetCookieJar(const Value: string);
    procedure SetCookieFile(const Value: string);
    procedure SetSslCipherList(const Value: string);

    function GetUrl: string;
    function GetProxy: string;
    function GetUserPwd: string;
    function GetProxyUserPwd: string;
    function GetRange: string;
    function GetPostFields: string;
    function GetReferer: string;
    function GetFtpPort: string;
    function GetUserAgent: string;
    function GetCookie: string;
    function GetSslCert: string;
    function GetSslCertPasswd: string;
    function GetCustomRequest: string;
    function GetInterface: string;
    function GetKrb4Level: string;
    function GetCaInfo: string;
    function GetRandomFile: string;
    function GetEgdSocket: string;
    function GetCookieJar: string;
    function GetCookieFile: string;
    function GetSslCipherList: string;

    function SetListOption(Option: CurlOption; const AList: TCurlRWList): Boolean;
    function SetHttpPostOption: Boolean;

    procedure SetHttpVersion(Value: Curl_http_version);
    procedure SetClosePolicy(Value: Curl_closepolicy);
    procedure SetProxyType(Value: Curl_proxytype);
    procedure SetWriteInfo(Value: string);
    function GetWriteInfo: string; // Not implemented
    procedure SetCookieSession(Value: Boolean);
    procedure SetCaPath(Value: string);
    function GetCaPath: string;
    procedure SetDnsCacheTimeout(Value: Longint);
    procedure SetDnsUseGlobalCache(Value: Boolean);
    procedure SetNoSignal(Value: Boolean);
    procedure SetEncoding(Value: CurlEncoding);
    procedure SetSslCertType(Value: CurlCertType);
    procedure SetSslKeyType(Value: CurlKeyType);
    procedure SetSslKey(Value: string);
    function GetSslKey: string;
    procedure SetSslVerifyHost(Value: CurlHostVerify);
    procedure SetSslEngine(Value: string);
    function GetSslEngine: string;
    procedure SetSslEngineDefault(Value: Boolean);
    procedure SetSslKeyPassword(Value: string);
    function GetSslKeyPassword: string;
    procedure SetBufferSize(Value: LongInt);

    procedure SetHeaderFunction(AHeaderFunc: Curl_write_callback);
    procedure SetHeaderStream(Value: Pointer);
    procedure SetOnHeader(AProc: TCurlHeaderEvent);
    procedure SetHeaderFile(Value: string);
    function GetHeaderFile: string;
    procedure InitHeaderFile;

    procedure SetWriteFunction(AWriteFunc: Curl_write_callback);
    procedure SetOutputStream(Value: Pointer);
    procedure SetOnReceive(AProc: TCurlReceiveEvent);
    procedure SetOutputFile(Value: string);
    function GetOutputFile: string;
    procedure InitOutputFile;

    procedure SetReadFunction(AReadFunc: Curl_read_callback);
    procedure SetInputStream(Value: Pointer);
    procedure SetOnTransmit(AProc: TCurlTransmitEvent);
    procedure SetInputFile(Value: string);
    function GetInputFile: string;
    procedure InitInputFile;

    procedure SetProgressFunction(const AFunc: Curl_progress_callback);
    procedure SetProgressData(AData: Pointer);
    procedure SetOnProgress(AProc: TCurlProgressEvent);

    procedure SetDebugFunction(AFunc: Curl_debug_callback);
    procedure SetDebugData(AData: Pointer);
    procedure SetOnDebug(AProc: TCurlDebugEvent);

    procedure SetError(Code: CurlCode; const Msg: string); // <- Generate a custom error message
    procedure SetErrorStream(Value: PIOFile);
    procedure SetErrorFile(Value: string);
    function GetErrorFile: string;
    function GetErrorBuffer: string;
    procedure SetErrorBuffer(const Value: string);
    // <- This is not exposed - the buffer is set in 'Create'
    procedure InitErrorFile;

    function GetCurlResult: CurlCode;

    procedure SetUnrestrictedAuth(const Value: Boolean);
    procedure SetFtpUseEPRT(const Value: Boolean);

    procedure SetHttpAuth(Value: CurlAuthenticationMethods);
    procedure SetProxyAuth(Value: CurlAuthenticationMethods);
    procedure SetFtpCreateMissingDirs(Value: Boolean);
    procedure SetFtpResponseTimeout(Value: LongInt);
    procedure SetIpResolve(Value: CurlResolverVersion);
    procedure SetMaxFileSize(Value: LongInt);
    procedure SetSslCtxData(Value: Pointer);
    procedure SetSslCtxFunction(Value: Curl_ssl_ctx_callback);

    function GetReadFunction: Curl_read_callback;
    procedure SetCookieListOption;
    procedure SetIoCtlCallback(Value: Curl_ioctl_callback);
    procedure SetIoCtlData(Value: Pointer);
    procedure SetTcpNoDelay(Value: Boolean);
    procedure SetNetRcFile(Value: string);
    function GetNetRcFile: string;
    procedure SetFtpAccount(Value: string);
    function GetFtpAccount: string;

    procedure SetSourceUserPwd(Value: string);
    procedure SetSourceUrl(Value: string);

    function GetSourceUserPwd: string;
    function GetSourceUrl: string;

    procedure SetFtpSsl(Value: Curl_ftpssl);
    procedure SetFtpAuth(Value: Curl_ftpauth);

    procedure SetIgnoreContentLength(const Value: Boolean);
    procedure SetFtpSkipPasvIp(const Value: Boolean);

    function GetHttpHeader: TCurlRWList;
    function GetQuote: TCurlRWList;
    function GetPostQuote: TCurlRWList;
    function GetPreQuote: TCurlRWList;
    function GetTelnetOptions: TCurlRWList;
    function GetHttp200Aliases: TCurlRWList;
    function GetSourcePreQuote: TCurlRWList;
    function GetSourceQuote: TCurlRWList;
    function GetSourcePostQuote: TCurlRWList;

  public
    function EffectiveUrl: string;
    function HttpCode: LongInt;
    function HeaderSize: LongWord;
    function RequestSize: LongWord;
    function SslVerifyResult: LongInt;
    function FileTime: LongInt;
    function TotalTime: Double;
    function NameLookupTime: Double;
    function ConnectTime: Double;
    function PreTransferTime: Double;
    function SizeUpload: LongWord;
    function SizeDownload: LongWord;
    function SpeedDownload: Double;
    function SpeedUpload: Double;
    function ContentLengthDownload: LongWord;
    function ContentLengthUpload: LongWord;
    function StartTransferTime: Double;
    function ContentType: string;
    function RedirectCount: LongInt;
    function RedirectTime: Double;

    function ResponseCode: LongInt;
    function HttpConnectCode: LongInt;
    function OsErrno: LongInt;
    function NumConnects: LongInt;

    function HttpAuthAvail: CurlAuthenticationMethods;
    function ProxyAuthAvail: CurlAuthenticationMethods;

    procedure UpdateSslEnginesList;

    procedure UpdateCookieList;

    class function Protocols: TCurlROList;
    class function VersionInfo: Curl_version_info_data;
    class function LibraryVersion: string;
    class function VersionNumber: LongWord;
    class function Machine: string;
    class function Features: TCurlFeatures;
    class function SslVersionString: string;
    class function SslVersionNumber: LongInt;
    class function LibzVersion: string;
    class function CurlVersion: string;
    class function AresVersionString: string;
    class function AresVersionNumber: LongInt;
    class function LibIdnVersion: string;

  public
    property ResultCode: CurlCode read GetCurlResult;
    property Handle: PCurl read FCurl;
    property ErrorString: string read GetErrorBuffer;
    property CrLf: Boolean read FCrLf write SetCrLf;
    property NetRc: CURL_NETRC_OPTION read FNetRc write SetNetRc;
    property HttpProxyTunnel: Boolean read FHttpProxyTunnel write SetHttpProxyTunnel;
    property SslVerifyPeer: Boolean read FSslVerifyPeer write SetSslVerifyPeer;
    property FreshConnect: Boolean read FFreshConnect write SetFreshConnect;
    property ForbidReuse: Boolean read FForbidReuse write SetForbidReuse;
    property HttpGet: Boolean read FHttpGet write SetHttpGet;
    property FtpUseEpsv: Boolean read FFtpUseEpsv write SetFtpUseEpsv;
    property RequestFiletime: Boolean read FFiletime write SetFiletime;
    property FtpAscii: Boolean read FFtpAscii write SetTransferText;
    property AutoReferer: Boolean read FAutoReferer write SetAutoReferer;
    property LowSpeedLimit: LongInt read FLowSpeedLimit write SetLowSpeedLimit;
    property LowSpeedTime: LongInt read FLowSpeedTime write SetLowSpeedTime;
    property ResumeFrom: LongInt read FResumeFrom write SetResumeFrom;
    property SslVersion: Curl_sslversion read FSslVersion write SetSslVersion;
    property TimeCondition: Curl_TimeCond read FTimeCondition write SetTimeCondition;
    property TimeValue: LongInt read FTimeValue write SetTimeValue;
    property ProxyPort: LongInt read FProxyPort write SetProxyPort;
    property PostFieldSize: LongInt read FPostFieldSize write SetPostFieldSize;
    property MaxRedirs: LongInt read FMaxRedirs write SetMaxRedirs;
    property MaxConnects: LongInt read FMaxConnects write SetMaxConnects;
    property ProxyUserPwd: string read GetProxyUserPwd write SetProxyUserPwd;
    property Range: string read GetRange write SetRange;
    property FtpPort: string read GetFtpPort write SetFtpPort;
    property SslCert: string read GetSslCert write SetSslCert;
    property SslCertPasswd: string read GetSslCertPasswd write SetSslCertPasswd;
    property CustomRequest: string read GetCustomRequest write SetCustomRequest;
    property NetInterface: string read GetInterface write SetInterface;
    property Krb4Level: string read GetKrb4Level write SetKrb4Level;
    property CaInfo: string read GetCaInfo write SetCaInfo;
    property RandomFile: string read GetRandomFile write SetRandomFile;
    property EgdSocket: string read GetEgdSocket write SetEgdSocket;
    property FollowLocation: Boolean read FFollowLocation write SetFollowLocation;
    property Header: Boolean read FHeader write SetHeader;
    property FtpListOnly: Boolean read FFtpListOnly write SetFtpListOnly;
    property FtpAppend: Boolean read FFtpAppend write SetFtpAppend;
    property TransferText: Boolean read FTransferText write SetTransferText;
    property HttpHeader: TCurlRWList read GetHttpHeader;
    property HttpPost: PCurl_HttpPost read FHttpPost write FHttpPost;
    property Quote: TCurlRWList read GetQuote;
    property PostQuote: TCurlRWList read GetPostQuote;
    property PreQuote: TCurlRWList read GetPreQuote;
    property TelnetOptions: TCurlRWList read GetTelnetOptions;
    property FormData: TMultiPartFormData read FFormData write FFormData;
    property Cookie: string read GetCookie write SetCookie;
    property CookieJar: string read GetCookieJar write SetCookieJar;
    property CookieSession: Boolean read FCookieSession write SetCookieSession;

    property NoBody: Boolean read FNoBody write SetNoBody;
    property Post: Boolean read FPost write SetPost; // OBSOLETE, PostFields sets this
    property Port: WORD read FPort write SetPort;
    property Put: Boolean read FPut write SetPut;
    property Timeout: LongInt read FTimeout write SetTimeout;
    property HttpVersion: Curl_http_version read FHttpVersion write SetHttpVersion;
    property ClosePolicy: Curl_closepolicy read FClosePolicy write SetClosePolicy;
    property ProxyType: Curl_proxytype read FProxyType write SetProxyType;
    property Encoding: CurlEncoding read FEncoding write SetEncoding;
    property SslCertType: CurlCertType read FSslCertType write SetSslCertType;
    property SslKeyType: CurlKeyType read FSslKeyType write SetSslKeyType;
    property WriteInfo: string read GetWriteInfo write SetWriteInfo; // Not implemented.
    property CaPath: string read GetCaPath write SetCaPath;
    property DnsCacheTimeout: LongInt read FDnsCacheTimeout write SetDnsCacheTimeout;
    property DnsUseGlobalCache: Boolean read FDnsUseGlobalCache write SetDnsUseGlobalCache;
    property NoSignal: Boolean read FNoSignal write SetNoSignal;
    property Http200Aliases: TCurlRWList read GetHttp200Aliases;
    property SslKey: string read GetSslKey write SetSslKey;
    property SslVerifyHost: CurlHostVerify read FSslVerifyHost write SetSslVerifyHost;
    property SslEngine: string read GetSslEngine write SetSslEngine;
    property SslEngineDefault: Boolean read FSslEngineDefault write SetSslEngineDefault;
    property SslCipherList: string read GetSslCipherList write SetSslCipherList;
    property SslKeyPassword: string read GetSslKeyPassword write SetSslKeyPassword;
    property BufferSize: LongInt read FBufferSize write SetBufferSize;
    property ErrorStream: PIOFile read FErrorStream write SetErrorStream;
    property ErrorFile: string read GetErrorFile write SetErrorFile;
    property NoProgress: Boolean read FNoProgress write SetNoProgress;
    property ProgressFunction: Curl_progress_callback read FProgressFunction
      write SetProgressFunction;
    property ProgressData: Pointer read FProgressData write SetProgressData;
    property Verbose: Boolean read FVerbose write SetVerbose;
    property DebugFunction: Curl_debug_callback read FDebugFunction write SetDebugFunction;
    property DebugData: Pointer read FDebugData write SetDebugData;

    property HeaderFunction: Curl_write_callback read FHeaderScheme.Callback
      write SetHeaderFunction;
    property HeaderStream: Pointer read FHeaderScheme.Stream write SetHeaderStream;
    property HeaderFile: string read GetHeaderFile write SetHeaderFile;
    property WriteFunction: Curl_write_callback read FReceiveScheme.Callback write SetWriteFunction;
    property OutputStream: Pointer read FReceiveScheme.Stream write SetOutputStream;
    property ReadFunction: Curl_read_callback read GetReadFunction write SetReadFunction;
    property InputStream: Pointer read FTransmitScheme.Stream write SetInputStream;
    property PrivateData: Pointer read FPrivateData write FPrivateData;
    property UnrestrictedAuth: Boolean read FUnrestrictedAuth write SetUnrestrictedAuth;
    property FtpUseEPRT: Boolean read FFtpUseEPRT write SetFtpUseEPRT;

    property HttpAuthenticationMethods: CurlAuthenticationMethods read FHttpAuth write SetHttpAuth;
    property ProxyAuthenticationMethods: CurlAuthenticationMethods read FProxyAuth
      write SetProxyAuth;
    property FtpCreateMissingDirs: Boolean read FFtpCreateMissingDirs write SetFtpCreateMissingDirs;
    property FtpResponseTimeout: LongInt read FFtpResponseTimeout write SetFtpResponseTimeout;
    property IpResolverVersion: CurlResolverVersion read FIpResolve write SetIpResolve;
    property MaxFileSize: Longint read FMaxFileSize write SetMaxFileSize;
    property SslCtxFunction: Curl_ssl_ctx_callback read FSslCtxFunction write SetSslCtxFunction;
    property SslCtxData: Pointer read FSslCtxData write SetSslCtxData;

    property CookieList: TCurlCookieList read FCookieList;
    property SslEnginesList: TCurlROList read FSslEnginesList;
    property IoCtlFunction: Curl_ioctl_callback read FIoCtlCallback write FIoCtlCallback;
    property IoCtlData: Pointer read FIoCtlData write SetIoCtlData;
    property TcpNoDelay: Boolean read FTcpNoDelay write SetTcpNoDelay;
    property NetRcFile: string read GetNetRcFile write SetNetRcFile;
    property FtpAccount: string read GetFtpAccount write SetFtpAccount;

    property SourcePreQuote: TCurlRWList read GetSourcePreQuote;
    property SourceQuote: TCurlRWList read GetSourceQuote;
    property SourcePostQuote: TCurlRWList read GetSourcePostQuote;
    property SourceUserPwd: string read GetSourceUserPwd write SetSourceUserPwd;
    property SourceUrl: string read GetSourceUrl write SetSourceUrl;
    property FtpSsl: Curl_ftpssl read FFtpSsl write SetFtpSsl;
    property FtpAuth: Curl_ftpauth read FFtpAuth write SetFtpAuth;

    property IgnoreContentLength: Boolean read FIgnoreContentLength write SetIgnoreContentLength;
    property FtpSkipPasvIp: Boolean read FFtpSkipPasvIp write SetFtpSkipPasvIp;

  published
    property ConnectTimeout: LongInt read FConnectTimeout write SetConnectTimeout;
    property CookieFile: string read GetCookieFile write SetCookieFile;
    property FailOnError: Boolean read FFailOnError write SetFailOnError;
    property InputFile: string read GetInputFile write SetInputFile;
    property OutputFile: string read GetOutputFile write SetOutputFile;
    property PostFields: string read GetPostFields write SetPostFields;
    property Proxy: string read GetProxy write SetProxy;
    property Referer: string read GetReferer write SetReferer;
    property URL: string read GetUrl write SetUrl;
    property Upload: Boolean read FUpload write SetUpload;
    property UserAgent: string read GetUserAgent write SetUserAgent;
    property UserPwd: string read GetUserPwd write SetUserPwd;

    property OnDebug: TCurlDebugEvent read FOnDebug write SetOnDebug;
    property OnHeader: TCurlHeaderEvent read FHeaderScheme.Hdr_event write SetOnHeader;
    property OnProgress: TCurlProgressEvent read FOnProgress write SetOnProgress;
    property OnReceive: TCurlReceiveEvent read FReceiveScheme.Rx_event write SetOnReceive;
    property OnTransmit: TCurlTransmitEvent read FTransmitScheme.Tx_event write SetOnTransmit;
    property OnListCookies: TCurlListCookiesEvent read FOnListCookies write FOnListCookies;
  public
    constructor Create(AOwner: TComponent);
    destructor Destroy; override;
    function Perform: Boolean;
    procedure Clear;
    procedure ListCookies;
    class function Escape(const S: string): string;
    class function UnEscape(const S: string): string;

  end;

implementation

{$HINTS OFF}
// Yes, Delphi - I know they are platform specific - didn't you read my ifdef ???
const
  FaReadOnly = SysUtils.FaReadOnly;
  FaVolumeID = SysUtils.FaVolumeID;
{$HINTS ON}

function FileIsWriteable(const FN: string): Boolean;
var
  R: TSearchRec;
  FH: Text;
begin
  if FileExists(FN) then
  begin
    R.Size := 0;
    FileIsWriteable := FindFirst(FN, FaAnyFile, R) = 0;
    if Result then
      Result := ((R.Attr and FaReadOnly) <= 0);
    SysUtils.FindClose(R);
  end
  else
  begin
    { Hell, I don't know - just try it and find out ... }
    Ioresult;
{$I-}
    AssignFile(FH, FN);
    Rewrite(FH);
    CloseFile(FH);
    Erase(FH);
    Result := IoResult = 0;
{$I+}
  end;
end;

function FileIsReadable(const FN: string): Boolean;
var
  R: TSearchRec;
begin
  R.Size := 0;
  Result := (FindFirst(FN, FaAnyFile, R) = 0) and ((R.Attr and FaDirectory) = 0) and
    ((R.Attr and FaVolumeID) = 0);
  SysUtils.FindClose(R);
end;

function GetFileSize(const FN: string): LongInt;
var
  R: TSearchRec;
begin
  R.Size := 0;
  if (FindFirst(FN, FaAnyFile, R) = 0) then
    Result := R.Size
  else
    Result := -1;
  SysUtils.FindClose(R);
end;

{ WRAPPERS FOR LINKED LISTS, LIKE CURL_SLIST AND CURL_HTTPPOST }

{ ========================================================= }
{ =================   tCurlROList  ======================== }
{ ========================================================= }

constructor TCurlROList.Create;
begin
  inherited Create;
  FList := nil;
  FCount := 0;
  FDirty := False;
end;

procedure TCurlROList.Add(const AStr: string);
var
  Tmp, P1, P2: PChar;
begin
  if (Pos(#10, AStr) = 0) then
  begin
    FList := Curl_slist_append(FList, PChar(AStr));
    Inc(FCount);
    FDirty := True;
  end
  else
  begin
    Tmp := StrNew(PChar(AStr));
    P1 := Tmp;
    repeat
      P1 := StrScan(P1, #13);
      if (P1 <> nil) then
        StrCopy(P1, @P1[1]);
    until (P1 = nil);
    P1 := Tmp;
    repeat
      P2 := StrScan(P1, #10);
      if (P2 <> nil) then
        P2^ := #0;
      FList := Curl_slist_append(FList, P1);
      Inc(FCount);
      if (P2 = nil) then
        BREAK;
      P1 := @P2[1];
    until False;
    StrDispose(Tmp);
  end;
end;

destructor TCurlROList.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TCurlROList.GetText: string;
var
  P: Pcurl_slist;
  L: LongInt;
begin
  if (FList <> nil) then
  begin
    L := 0;
    P := FList;
    while (P <> nil) do
    begin
      Inc(L, 1);
      if (P^.Data <> nil) then
        Inc(L, StrLen(P^.Data));
      P := P^.Next;
    end;
    SetLength(Result, L);
    Result := '';
    P := FList;
    while (P <> nil) do
    begin
      Result := Result + P^.Data + #10;
      P := P^.Next;
    end;
  end
  else
    Result := '';
end;

procedure TCurlROList.SetText(const AStr: string);
begin
  Clear;
  if (AStr <> '') then
    Add(AStr);
end;

procedure TCurlROList.Clear;
begin
  Curl_slist_free_all(FList);
  FList := nil;
  FCount := 0;
  FDirty := True;
end;

function TCurlROList.GetItemPtr(N: LongInt): Pcurl_slist;
var
  I: LongInt;
begin
  I := 0;
  Result := FList;
  while (Result <> nil) do
  begin
    if (I = N) then
      EXIT;
    Result := Result^.Next;
    Inc(I);
  end;
  Result := nil;
end;

function TCurlROList.GetItems(N: LongInt): string;
var
  P: Pcurl_slist;
begin
  P := GetItemPtr(N);
  if (P <> nil) then
    Result := P^.Data
  else
    Result := '';
end;

procedure TCurlROList.SetItems(N: LongInt; const S: string);
var
  P: Pcurl_slist;
  L: LongInt;
begin
  P := GetItemPtr(N);
  if (P <> nil) then
  begin
    if (P^.Data <> nil) then
      _free(P^.Data);
    L := Length(S);
    P^.Data := Malloc(L + 1);
    FillChar(P^.Data^, L + 1, #0);
    StrLCopy(P^.Data, PChar(S), L);
    FDirty := True;
  end;
end;

procedure TCurlROList.Delete(N: LongInt);
var
  Prev, Me: Pcurl_slist;
begin
  Me := GetItemPtr(N);
  if (Me <> nil) then
  begin
    if (FList = Me) then
    begin
      FList := Me^.Next;
    end
    else
    begin
      Prev := GetItemPtr(N - 1);
      Prev^.Next := Me^.Next;
    end;
    Me^.Next := nil;
    Curl_slist_free_all(Me);
    FDirty := True;
  end;
end;

{ ========================================================= }
{ =================   tCurlRWList  ======================== }
{ ========================================================= }

procedure TCurlRWList.Add(const AStr: string);
begin
  inherited;
end;

procedure TCurlRWList.Delete(N: LongInt);
begin
  inherited;
end;

procedure TCurlRWList.Clear;
begin
  inherited;
end;

{ ========================================================= }
{ ==============   tMultiPartFormData   =================== }
{ ========================================================= }

constructor TMultiPartFormData.Create;
begin
  inherited Create;
  FErrCode := CURLE_OK;
  FHttpPost := nil;
end;

destructor TMultiPartFormData.Destroy;
begin
  DoClear(FHttpPost);
  inherited Destroy;
end;

procedure TMultiPartFormData.Append(const PostInfo: Curl_HttpPost);
begin
  DoAppend(FHttpPost, PostInfo);
end;

procedure CopyList(const Source: Pcurl_slist; var Target: Pcurl_slist);
var
  VList: Pcurl_slist;
  VStr: string;
begin
  if (Source <> nil) then
  begin
    VList := Source;
    while (VList <> nil) do
    begin
      if (VList^.Data <> nil) then
      begin
        VStr := StrPas(VList^.Data) + #0;
        Curl_slist_append(Target, @VStr[1]);
      end;
      VList := VList^.Next;
    end;
  end
  else
    Target := nil;
end;

procedure TMultiPartFormData.DoAppend(var APost: PCurl_HttpPost; const PostInfo: Curl_HttpPost);
var
  NewPost, LastPost: Pcurl_HttpPost;
begin
  New(NewPost);
  with NewPost^ do
  begin

    Namelength := (StrLen(PostInfo.Name));
    name := StrAlloc(Namelength + 1);
    StrCopy(name, PostInfo.Name);

    Contentslength := PostInfo.ContentsLength;
    Contents := Stralloc(Contentslength + 1);
    StrCopy(Contents, Postinfo.Contents);

    Contenttype := StrAlloc(StrLen(Postinfo.Contenttype) + 1);
    StrCopy(Contenttype, PostInfo.Contenttype);

    Flags := PostInfo.Flags;

    if (PostInfo.ContentHeader <> nil) then
      CopyList(PostInfo.Contentheader, ContentHeader);
    if (PostInfo.More <> nil) then
      DoAppend(More, PostInfo.More^);

    Next := nil;

  end;
  if (APost = nil) then
    APost := NewPost
  else
  begin
    LastPost := APost;
    while (LastPost <> nil) and (LastPost^.Next <> nil) do
      LastPost := LastPost^.Next;
    LastPost^.Next := NewPost;
  end;

end;

procedure TMultiPartFormData.Add(const AName: string; const AContents: string;
  const AContentType: string; APostType: TCurlPostType);
var
  NewPost: PCurl_HttpPost;
begin
  New(NewPost);
  with NewPost^ do
  begin
    Namelength := Length(AName);
    name := StrAlloc(Namelength + 1);
    StrPCopy(name, AName);
    Contentslength := Length(AContents);
    Contents := StrAlloc(Contentslength + 1);
    StrPCopy(Contents, AContents);
    Contenttype := StrAlloc(Length(AContentType) + 1);
    StrPCopy(Contenttype, AContentType);
    Flags := HTTPPOST_PTRNAME or HTTPPOST_PTRCONTENTS;
    case APostType of
      POST_TYPE_ATTACHMENT:
        Flags := Flags or HTTPPOST_FILENAME;
      POST_TYPE_FILEDATA:
        Flags := Flags or HTTPPOST_READFILE;
    end;
    if (APostType in [POST_TYPE_ATTACHMENT, POST_TYPE_FILEDATA]) and (not FileIsReadable(AContents))
    then
      FErrCode := CURLE_READ_ERROR;
    Contentheader := nil;
    More := nil;
    Next := FHttpPost;
  end;
  FHttpPost := NewPost;
end;

procedure TMultiPartFormData.Clear;
begin
  DoClear(FHttpPost);
end;

procedure TMultiPartFormData.DoClear(var APost: PCurl_HttpPost);
var
  ThisPost, NextPost: PCurl_HttpPost;
begin
  ThisPost := APost;
  while (ThisPost <> nil) do
  begin
    NextPost := ThisPost^.Next;
    with ThisPost^ do
    begin
      StrDispose(name);
      StrDispose(Contents);
      StrDispose(Contenttype);
      if (More <> nil) then
        DoClear(More); { ... Recursive }
      if (Contentheader <> nil) then
        Curl_slist_free_all(Contentheader);
    end;
    FreeMem(ThisPost);
    ThisPost := NextPost;
  end;
  APost := nil;
end;

{ ========================================================= }
{ ===============  tCurlCookieList   ====================== }
{ ========================================================= }

constructor TCurlCookieList.Create(AOwner: TObject);
begin
  inherited Create;
  FOwner := AOwner;
  FHandle := TCurl(AOwner).Handle;
  FList := nil;
  FState := [];
end;

destructor TCurlCookieList.Destroy;
begin
  if (COOKIES_OBJ_STALE in FState) then
    SendListToLib;
  Curl_slist_free_all(FList);
  inherited Destroy;
end;

function TCurlCookieList.Add(const Cookie: Ansistring): Boolean;
var
  N: LongInt;
  P: PChar;
begin
  N := 0;
  P := PChar(Cookie);
  while (P^ <> #0) do
  begin
    if P^ = #9 then
      Inc(N);
    Inc(P);
  end;
  P := PChar(Cookie);
  Result := (N = 6) or (StrLIComp('SET-COOKIE:', P, 11) = 0);
  if Result then
  begin
    FList := Curl_slist_append(FList, P);
    if (not(COOKIES_LIB_STALE in FState)) then
      FState := FState + [COOKIES_LIB_STALE];
  end;
end;

function TCurlCookieList.AddFromFile(const Filename: Ansistring): CurlCode;
var
  F: System.Text;
  S: Ansistring;
begin
  S := '';
  if FileIsReadable(Filename) then
  begin
{$I-}
    Assign(F, Filename);
    Reset(F);
    if (Ioresult = 0) then
    begin
      while not Eof(F) do
      begin
        ReadLn(F, S);
        Add(S);
      end;
      Result := CURLE_OK;
    end
    else
      Result := CURLE_READ_ERROR;
{$I+}
    Close(F);
  end
  else
    Result := CURLE_READ_ERROR;
end;

procedure TCurlCookieList.ForEachCookie(Callback: TCurlEnumCookiesFunction; User_data: Pointer);
var
  P1: Pcurl_slist;
begin
  if (COOKIES_LIB_STALE in FState) then
    GetListFromLib;
  P1 := FList;
  while (P1 <> nil) do
  begin
    if not Callback(Self, P1^.Data, User_data) then
      BREAK;
    P1 := P1^.Next;
  end;
end;

procedure TCurlCookieList.RemoveDuplicates;
var
  Curr, Prev: Pcurl_slist;
  Needle: Pcurl_slist;
  H: LongInt;
  L: LongInt;
begin
  Needle := FList;
  while (Needle <> nil) do
  begin
    if (Needle^.Data <> nil) then
    begin
      Prev := nil;
      Curr := Needle;
      L := StrLen(Needle^.Data);
      H := PLongInt(Needle^.Data)^;
      while (Curr <> nil) do
      begin
        if (Curr <> Needle) and (Curr^.Data <> nil) and (H = PLongInt(Curr^.Data)^) and
          (Curr^.Data[L] = #0) and (StrLComp(Curr^.Data, Needle^.Data, L) = 0) then
        begin
          if (Curr^.Data = Needle^.Data) then
            Curr^.Data := nil;
          Prev^.Next := Curr^.Next;
          Curr^.Next := nil;
          Curl_slist_free_all(Curr);
          Curr := Prev^.Next;
        end
        else
        begin
          Prev := Curr;
          Curr := Curr^.Next;
        end;
      end;
    end;
    Needle := Needle^.Next;
  end;
end;

procedure TCurlCookieList.Clear;
begin
  Curl_slist_free_all(FList);
  FList := nil;
  if (FOwner <> nil) and (FHandle <> nil) then
    Curl_easy_setopt(FHandle, CURLOPT_COOKIELIST, 'ALL');
  FState := [];
end;

function TCurlCookieList.GetListFromLib: CurlCode;
var
  Tmp, P1: Pcurl_slist;
begin
  Result := Curl_easy_getinfo(FHandle, CURLINFO_COOKIELIST, Tmp);
  if (Result = CURLE_OK) then
  begin
    if (FList <> nil) then
    begin
      P1 := FList;
      while (P1 <> nil) do
      begin
        if (P1^.Next = nil) then
        begin
          P1^.Next := Tmp;
          P1 := nil;
        end
        else
          P1 := P1^.Next;
      end;
    end
    else
      FList := Tmp;
    RemoveDuplicates;
    if (COOKIES_OBJ_STALE in FState) then
      FState := FState - [COOKIES_OBJ_STALE];
  end;
end;

function TCurlCookieList.SendListToLib: CurlCode;
var
  P1: Pcurl_slist;
begin
  Result := CURLE_OK;
  P1 := FList;
  while (P1 <> nil) do
  begin
    if (P1^.Data <> nil) then
    begin
      Result := Curl_easy_setopt(FHandle, CURLOPT_COOKIELIST, P1^.Data);
      if (Result <> CURLE_OK) then
        BREAK;
    end;
    P1 := P1^.Next;
  end;
  if (Result = CURLE_OK) then
  begin
    if (FList <> nil) then
    begin
      Curl_slist_free_all(FList);
      FList := nil;
    end;
    if (COOKIES_LIB_STALE in FState) then
      FState := FState - [COOKIES_LIB_STALE];
  end;
end;

type
  PTextFile = ^Text;

function FileSaveCB(Sender: TObject; const Cookie: Ansistring; User_data: Pointer): Boolean;
begin
  WriteLn(PTextFile(User_data)^, Cookie);
  Result := (Ioresult = 0);
end;

function TCurlCookieList.SaveToFile(const Filename: Ansistring): CurlCode;
var
  F: Text;
begin
  if FileIsWriteable(Filename) then
  begin
{$I-}
    Assign(F, Filename);
    Rewrite(F);
    if (Ioresult = 0) then
    begin
      ForEachCookie(@FileSaveCB, @F);
      Close(F);
      if (Ioresult = 0) then
        Result := CURLE_OK
      else
        Result := CURLE_WRITE_ERROR;
    end
    else
      Result := CURLE_WRITE_ERROR;
{$I+}
  end
  else
    Result := CURLE_WRITE_ERROR;
end;

var
  GlobalProtoColList: TCurlROList;
  GlobalVersionInfoData: Curl_version_info_data;
  GlobalFeatures: TCurlFeatures;

class function TCurl.LibraryVersion: string;
begin
  Result := StrPas(GlobalVersionInfoData.Version);
end;

class function TCurl.VersionNumber: LongWord;
begin
  Result := GlobalVersionInfoData.Version_num;
end;

class function TCurl.Machine: string;
begin
  Result := StrPas(GlobalVersionInfoData.Host);
end;

class function TCurl.Features: TCurlFeatures;
begin
  Result := GlobalFeatures;
end;

class function TCurl.SslVersionString: string;
begin
  Result := StrPas(GlobalVersionInfoData.Ssl_version);
  // for some reason this string has a leading blank...
  while (Result <> '') and (Result[1] = #32) do
    Delete(Result, 1, 1);
end;

class function TCurl.SslVersionNumber: LongInt;
begin
  Result := GlobalVersionInfoData.Ssl_version_num;
end;

class function TCurl.LibzVersion: string;
begin
  Result := StrPas(GlobalVersionInfoData.Libz_version);
end;

class function TCurl.Protocols: TCurlROList;
begin
  Result := GlobalProtocolList;
end;

class function TCurl.VersionInfo: Curl_version_info_data;
begin
  Result := GlobalVersionInfoData;
end;

class function TCurl.CurlVersion: string;
begin
  Result := StrPas(Curl_version);
end;

class function TCurl.AresVersionString: string;
begin
  Result := StrPas(GlobalVersionInfoData.Ares);
end;

class function TCurl.AresVersionNumber: LongInt;
begin
  Result := GlobalVersionInfoData.Ares_num;
end;

class function TCurl.LibIdnVersion: string;
begin
  Result := StrPas(GlobalVersionInfoData.Libidn);
end;

procedure InitFeatures;
begin
  with GlobalFeatures, GlobalVersionInfoData do
  begin
    Ipv6 := (Features and CURL_VERSION_IPV6) > 0;
    Kerberos4 := (Features and CURL_VERSION_KERBEROS4) > 0;
    Ssl := (Features and CURL_VERSION_SSL) > 0;
    Libz := (Features and CURL_VERSION_LIBZ) > 0;
    Ntlm := (Features and CURL_VERSION_NTLM) > 0;
    GssNegotiate := (Features and CURL_VERSION_GSSNEGOTIATE) > 0;
    Debug := (Features and CURL_VERSION_DEBUG) > 0;
    AsynchDns := (Features and CURL_VERSION_ASYNCHDNS) > 0;
    Spnego := (Features and CURL_VERSION_SPNEGO) > 0;
    LargeFile := (Features and CURL_VERSION_LARGEFILE) > 0;
    Idn := (Features and CURL_VERSION_IDN) > 0;
    Sspi := (Features and CURL_VERSION_SSPI) > 0;
  end;
end;

function InitProtocolList: TCurlROList;
var
  Pp: PpChar;
begin
  Result := TCurlROList.Create;
  Pp := Curl_version_info(CURLVERSION_NOW)^.Protocols;
  repeat
    Result.Add(Pp^);
    Inc(Pp);
  until (Pp^ = nil);
end;

function GetStringProp(const Field: PChar): string; forward;

function TCurl.EffectiveUrl: string;
var
  Buff: PChar;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_EFFECTIVE_URL, Buff);
  Result := GetStringProp(Buff);
end;

function TCurl.ContentType: string;
var
  Buff: PChar;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_CONTENT_TYPE, Buff);
  Result := GetStringProp(Buff);
end;

function TCurl.HttpCode: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_HTTP_CODE, Result);
end;

function TCurl.HeaderSize: LongWord;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_HEADER_SIZE, Result);
end;

function TCurl.RequestSize: LongWord;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_REQUEST_SIZE, Result);
end;

function TCurl.SslVerifyResult: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_SSL_VERIFYRESULT, Result);
end;

function TCurl.FileTime: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_FILETIME, Result);
end;

function TCurl.TotalTime: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_TOTAL_TIME, Result);
end;

function TCurl.NameLookuptime: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_NAMELOOKUP_TIME, Result);
end;

function TCurl.ConnectTime: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_CONNECT_TIME, Result);
end;

function TCurl.PreTransferTime: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_PRETRANSFER_TIME, Result);
end;

function TCurl.SizeUpload: LongWord;
var
  DVal: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_SIZE_UPLOAD, DVal);
  Result := LongWord(Round(DVal));
end;

function TCurl.SizeDownload: LongWord;
var
  DVal: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_SIZE_DOWNLOAD, DVal);
  Result := LongWord(Round(DVal));
end;

function TCurl.SpeedDownload: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_SPEED_DOWNLOAD, Result);
end;

function TCurl.SpeedUpload: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_SPEED_UPLOAD, Result);
end;

function TCurl.StartTransferTime: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_STARTTRANSFER_TIME, Result);
end;

function TCurl.ContentLengthDownload: LongWord;
var
  DVal: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_CONTENT_LENGTH_DOWNLOAD, DVal);
  Result := LongWord(Round(DVal));
end;

function TCurl.ContentLengthUpload: LongWord;
var
  DVal: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_CONTENT_LENGTH_UPLOAD, DVal);
  Result := LongWord(Round(DVal));
end;

function TCurl.RedirectCount: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_REDIRECT_COUNT, Result);
end;

function TCurl.RedirectTime: Double;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_REDIRECT_TIME, Result);
end;

{ new===>>> }

function TCurl.ResponseCode: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_RESPONSE_CODE, Result);
end;

function TCurl.HttpConnectCode: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_HTTP_CONNECTCODE, Result);
end;

function TCurl.NumConnects: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_NUM_CONNECTS, Result);
end;

function TCurl.OsErrno: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_OS_ERRNO, Result);
end;

function IntToAuth(Methods: LongInt): CurlAuthenticationMethods;
begin
  Result := [];
  if ((Methods or CURLAUTH_BASIC)) > 0 then
    Result := Result + [AUTH_BASIC];
  if ((Methods or CURLAUTH_DIGEST)) > 0 then
    Result := Result + [AUTH_DIGEST];
  if ((Methods or CURLAUTH_GSSNEGOTIATE)) > 0 then
    Result := Result + [AUTH_GSSNEGOTIATE];
  if ((Methods or CURLAUTH_NTLM)) > 0 then
    Result := Result + [AUTH_NTLM];
end;

function TCurl.HttpAuthAvail: CurlAuthenticationMethods;
var
  Tmp: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_HTTPAUTH_AVAIL, Tmp);
  Result := IntToAuth(Tmp);
end;

function TCurl.ProxyAuthAvail: CurlAuthenticationMethods;
var
  Tmp: LongInt;
begin
  Curl_easy_getinfo(FCurl, CURLINFO_PROXYAUTH_AVAIL, Tmp);
  Result := IntToAuth(Tmp);
end;

procedure TCurl.UpdateSslEnginesList;
var
  P: Pcurl_slist;
begin
  FSslEnginesList.Clear;
  Curl_easy_getinfo(FCurl, CURLINFO_SSL_ENGINES, FSslEnginesList.FList);
  P := FSslEnginesList.FList;
  while (P <> nil) do
  begin
    Inc(FSslEnginesList.FCount);
    P := P^.Next;
  end;
end;

{ CALLBACKS AND DATA POINTERS FOR FILE I/O }

const
  Stdin = 0;
  Stdout = 1;

function FuncPtr(const APtr: PPointer): Pointer; {$IFDEF FPC} inline; {$ENDIF}
begin
  // Function pointers in FreePascal's OBJFPC mode are different than Borland's -
  // This function cleans up all the {$IFDEF FPC}@{$ENDIF} stuff...
  Result := APtr;
end;

{ ******** RESPONSE HEADERS ******** }
function DoHeader(Ptr: Pchar; Size, Nmemb: Size_t; PClient: TCurl): Size_t; cdecl;
var
  BContinue: Boolean;
  I: LongWord;
  Hdr: string;
begin
  PClient.MutexLock();
  BContinue := True;
  Result := (Size * Nmemb);
  with PClient, FHeaderScheme do
  begin
    if (@Hdr_event <> nil) then
    begin
      SetLength(Hdr, Result);
      Hdr[Result] := #0;
      for I := 0 to Result - 1 do
        if (Ptr[I] in [#10, #13]) then
          Hdr[I + 1] := #0
        else
          Hdr[I + 1] := Ptr[I];
      SetLength(Hdr, AnsiStrings.StrLen(@Hdr[1]));
      Hdr_event(TCurl(PClient), Hdr, BContinue);
      if BContinue and (Fs_type = FST_FILENAME) then
        Result := Size * Fwrite(Ptr, Size, Nmemb, Stream);
    end;
  end;
  if not BContinue then
    Result := 0;
  PClient.MutexUnlock();
end;

procedure TCurl.SetOnHeader(AProc: TCurlHeaderEvent);
begin
  FHeaderScheme.Hdr_event := AProc;
  with FHeaderScheme do
    if (FuncPtr(@AProc) <> nil) then
      Cb_type := CBT_EVENT
    else if (Cb_type = CBT_EVENT) then
      Cb_type := CBT_INTERNAL;
end;

procedure TCurl.SetHeaderFunction(AHeaderFunc: Curl_write_callback);
begin
  FHeaderScheme.Callback := AHeaderFunc;
  with FHeaderScheme do
    if (FuncPtr(@AHeaderFunc) <> nil) then
      Cb_type := CBT_CALLBACK
    else if (Cb_type = CBT_CALLBACK) then
      Cb_type := CBT_INTERNAL;
end;

procedure TCurl.SetHeaderStream(Value: Pointer);
begin
  FHeaderScheme.Stream := Value;
  if (Value <> nil) then
    FHeaderScheme.Fs_type := FST_STREAM
  else if (FHeaderScheme.Fs_type = FST_STREAM) then
    FHeaderScheme.Fs_type := FST_INTERNAL;
end;

procedure TCurl.SetHeaderFile(Value: string);
begin
  SetStringProp(FHeaderScheme.Filename, Value);
  if (Value <> '') then
    FHeaderScheme.Fs_type := FST_FILENAME
  else if (FHeaderScheme.Fs_type = FST_FILENAME) then
    FHeaderScheme.Fs_type := FST_INTERNAL;
end;

procedure TCurl.InitHeaderFile;
var
  TmpFunc, TmpStrm: Pointer;
begin
  TmpFunc := nil;
  TmpStrm := nil;
  with FHeaderScheme do
    case Cb_type of
      CBT_CALLBACK:
        begin
          TmpFunc := FuncPtr(@Callback);
          TmpStrm := Stream;
        end;
      CBT_EVENT:
        begin
          TmpFunc := @DoHeader;
          TmpStrm := Self;
          if (Fs_type = FST_FILENAME) then
          begin
            Stream := Fopen(Filename, 'w'#0);
            if (Stream = nil) then
              SetError(CURLE_WRITE_ERROR, 'Error writing headers to local file');
          end;
        end;
      CBT_INTERNAL:
        begin
          TmpFunc := @Fwrite;
          case Fs_type of
            FST_STREAM:
              begin
                TmpStrm := Stream;
                if (TmpStrm = nil) then
                  SetError(CURLE_WRITE_ERROR, 'Invalid header stream for internal callback');
              end;
            FST_FILENAME:
              begin
                TmpStrm := Fopen(Filename, 'w'#0);
                Stream := TmpStrm;
                if (TmpStrm = nil) then
                  SetError(CURLE_WRITE_ERROR, 'Error writing headers to local file');
              end;
            FST_INTERNAL:
              begin
                if (FNoBody or FHeader) then
                begin
                  TmpStrm := Fdopen(Stdout, 'w'#0);
                  if (TmpStrm = nil) then
                    SetError(CURLE_WRITE_ERROR, 'Error writing headers to standard output');
                end
                else
                begin
                  // TmpStrm:=fopen(pChar(CURL_NULL_FILE), 'w'#0);
                  // stream:=TmpStrm;
                  { <<== Revised 2005-09-29:
                    Don't waste a file descriptor here, set HeaderFunction to nil instead. ==>> }
                  TmpFunc := nil;
                  TmpStrm := nil;
                  Stream := nil;
                end;
              end;
          end
        end;
    end;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_HEADERFUNCTION, TmpFunc), CURLOPT_HEADERFUNCTION);
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_WRITEHEADER, TmpStrm), CURLOPT_WRITEHEADER);
end;

{ ******  INCOMING DATA  ******* }
function DoReceive(Ptr: Pointer; Size, Nmemb: LongWord; PClient: TCurl): LongWord; cdecl;
var
  BContinue: Boolean;
begin
  PClient.MutexLock();
  BContinue := True;
  Result := (Size * Nmemb);
  with PClient, FReceiveScheme do
  begin
    if (@Rx_event <> nil) then
      Rx_event(PClient, Ptr, Result, BContinue);
    if BContinue and (Fs_type = FST_FILENAME) then
      Result := Size * Fwrite(Ptr, Size, Nmemb, Stream);
  end;
  if not BContinue then
    Result := 0;
  PClient.MutexUnlock();
end;

procedure TCurl.SetOnReceive(AProc: TCurlReceiveEvent);
begin
  FReceiveScheme.Rx_event := AProc;
  with FReceiveScheme do
    if (FuncPtr(@AProc) <> nil) then
      Cb_type := CBT_EVENT
    else if (Cb_type = CBT_EVENT) then
      Cb_type := CBT_INTERNAL;
end;

procedure TCurl.SetWriteFunction(AWriteFunc: Curl_write_callback);
begin
  FReceiveScheme.Callback := AWriteFunc;
  with FReceiveScheme do
    if (FuncPtr(@AWriteFunc) <> nil) then
    begin
      Cb_type := CBT_CALLBACK;
    end
    else if (Cb_type = CBT_CALLBACK) then
      Cb_type := CBT_INTERNAL;
end;

procedure TCurl.SetOutputStream(Value: Pointer);
begin
  FReceiveScheme.Stream := Value;
  with FReceiveScheme do
    if (Value <> nil) then
    begin
      Fs_type := FST_STREAM;
    end
    else if (Fs_type = FST_STREAM) then
      Fs_type := FST_INTERNAL;
end;

procedure TCurl.SetOutputFile(Value: string);
begin
  SetStringProp(FReceiveScheme.Filename, Value);
  with FReceiveScheme do
    if (Value <> '') then
      Fs_type := FST_FILENAME
    else if (Fs_type = FST_FILENAME) then
      Fs_type := FST_INTERNAL;
end;

procedure TCurl.InitOutputFile;
var
  TmpFunc, TmpStrm: Pointer;
const
  ModeWrite: PChar = 'wb'; { ... Write binary for win32 ! }
  ModeAppend: PChar = 'ab';
begin
  TmpFunc := nil;
  TmpStrm := nil;
  with FReceiveScheme do
    case Cb_type of
      CBT_CALLBACK:
        begin
          TmpFunc := FuncPtr(@Callback);
          TmpStrm := Stream;
        end;
      CBT_EVENT:
        begin
          TmpFunc := @DoReceive;
          TmpStrm := Self;
          if (Fs_type = FST_FILENAME) then
          begin
            if (FResumeFrom <= 0) then
              Stream := Fopen(Filename, ModeWrite)
            else
              Stream := Fopen(Filename, ModeAppend); { <- 'append' if resuming a download }
            if (Stream = nil) then
              SetError(CURLE_WRITE_ERROR, 'Error writing to file');
          end;
        end;
      CBT_INTERNAL:
        begin
          TmpFunc := @Fwrite;
          case Fs_type of
            FST_STREAM:
              begin
                TmpStrm := Stream;
                if (TmpStrm = nil) then
                  SetError(CURLE_WRITE_ERROR, 'Invalid receive stream for internal callback');
              end;
            FST_FILENAME:
              begin
                if (FResumeFrom <= 0) then
                  TmpStrm := Fopen(Filename, ModeWrite)
                else
                  TmpStrm := Fopen(Filename, ModeAppend); { <- 'append' if resuming a download }
                Stream := TmpStrm;
                if (TmpStrm = nil) then
                  SetError(CURLE_WRITE_ERROR, 'Error writing to local file');
              end;
            FST_INTERNAL:
              begin
                TmpStrm := Fdopen(Stdout, 'w'#0);
                if (TmpStrm = nil) then
                  SetError(CURLE_WRITE_ERROR, 'Error writing to standard output');
              end;
          end;
        end;
    end;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_WRITEFUNCTION, TmpFunc), CURLOPT_WRITEFUNCTION);
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_FILE, TmpStrm), CURLOPT_FILE);
end;

{ ******* OUTGOING DATA ******* }
function DoTransmit(Ptr: Pointer; Size, Nmemb: LongWord; PClient: TCurl): LongWord; cdecl;
begin
  PClient.MutexLock();
  Result := (Size * Nmemb);
  with PClient, FTransmitScheme do
  begin
    if (@Tx_event <> nil) then
      Tx_event(PClient, Ptr, Result);
    if (Result > 0) and (Fs_type = FST_FILENAME) then
      Result := Fread(Ptr, 1, Result, Stream);
  end;
  PClient.MutexUnlock();
end;

procedure TCurl.SetOnTransmit(AProc: TCurlTransmitEvent);
begin
  FTransmitScheme.Tx_event := AProc;
  with FTransmitScheme do
    if (FuncPtr(@AProc) <> nil) then
      Cb_type := CBT_EVENT
    else if (Cb_type = CBT_EVENT) then
      Cb_type := CBT_INTERNAL;
end;

procedure TCurl.SetReadFunction(AReadFunc: Curl_read_callback);
begin
  FTransmitScheme.Callback := AReadFunc;
  with FTransmitScheme do
    if (FuncPtr(@AReadFunc) <> nil) then
    begin
      Cb_type := CBT_CALLBACK;
    end
    else if (Cb_type = CBT_CALLBACK) then
      Cb_type := CBT_INTERNAL;
end;

procedure TCurl.SetInputStream(Value: Pointer);
begin
  FTransmitScheme.Stream := Value;
  with FTransmitScheme do
    if (Value <> nil) then
    begin
      Fs_type := FST_STREAM;
    end
    else if (Fs_type = FST_STREAM) then
      Fs_type := FST_INTERNAL;
end;

procedure TCurl.SetInputFile(Value: string);
begin
  SetStringProp(FTransmitScheme.Filename, Value);
  with FTransmitScheme do
    if (Value <> '') then
      Fs_type := FST_FILENAME
    else if (Fs_type = FST_FILENAME) then
      Fs_type := FST_INTERNAL;
end;

procedure TCurl.InitInputFile;
var
  TmpFunc, TmpStrm: Pointer;

const
  ModeRead: PChar = {$IFDEF WIN32}'rb'{$ELSE}'r'{$ENDIF}; { ... Binary input for win32 ! }

begin
  TmpFunc := nil;
  TmpStrm := nil;
  with FTransmitScheme do
    case Cb_type of
      CBT_CALLBACK:
        begin
          TmpFunc := FuncPtr(@Callback);
          TmpStrm := Stream;
        end;
      CBT_EVENT:
        begin
          TmpFunc := @DoTransmit;
          TmpStrm := Self;
          if (Fs_type = FST_FILENAME) then
          begin
            if (FInFilesize < 0) then
              SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_INFILESIZE, GetFileSize(Filename)),
                CURLOPT_INFILESIZE);
            Stream := Fopen(Filename, ModeRead);
            if (Stream = nil) then
              SetError(CURLE_READ_ERROR, 'Error reading file');
          end;
        end;
      CBT_INTERNAL:
        begin
          TmpFunc := @Fread;
          case Fs_type of
            FST_STREAM:
              begin
                TmpStrm := Stream;
                if (TmpStrm = nil) then
                  SetError(CURLE_READ_ERROR, 'Invalid transmit stream for internal callback');
              end;
            FST_FILENAME:
              begin
                if (FInFilesize < 0) then
                  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_INFILESIZE, GetFileSize(Filename)),
                    CURLOPT_INFILESIZE);
                TmpStrm := Fopen(Filename, ModeRead);
                Stream := TmpStrm;
                if (TmpStrm = nil) then
                  SetError(CURLE_READ_ERROR, 'Error reading local file');
              end;
            FST_INTERNAL:
              begin
                TmpStrm := Fdopen(Stdin, ModeRead);
                if (TmpStrm = nil) then
                  SetError(CURLE_READ_ERROR, 'Error reading standard input');
              end;
          end;
        end;
    end;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_READFUNCTION, TmpFunc), CURLOPT_READFUNCTION);
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_INFILE, TmpStrm), CURLOPT_INFILE);
end;

function DoProgress(PClient: TCurl; Dltotal, Dlnow, Ultotal, Ulnow: Double): LongInt; cdecl;
var
  BContinue: Boolean;
begin
  TCurl(PClient).MutexLock();
  BContinue := True;
  with PClient do
    if (@FOnProgress <> nil) then
    begin
      if (UlTotal + UlNow) = 0 then
        FOnProgress(PClient, LongInt(Round(DlTotal)), LongInt(Round(DlNow)), BContinue)
      else
        FOnProgress(PClient, LongInt(Round(UlTotal)), LongInt(Round(UlNow)), BContinue);
    end;
  if BContinue then
    DoProgress := 0
  else
    DoProgress := 1;
  TCurl(PClient).MutexUnlock();
end;

procedure TCurl.SetOnProgress(AProc: TCurlProgressEvent);
begin
  FOnProgress := AProc;
  if (FuncPtr(@AProc) <> nil) then
  begin
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PROGRESSFUNCTION, @DoProgress),
      CURLOPT_PROGRESSFUNCTION);
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PROGRESSDATA, Self), CURLOPT_PROGRESSDATA);
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_NOPROGRESS, LongInt(False)), CURLOPT_NOPROGRESS);
  end
  else
  begin
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PROGRESSFUNCTION, nil), CURLOPT_PROGRESSFUNCTION);
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_NOPROGRESS, LongInt(True)), CURLOPT_NOPROGRESS);
  end;
end;

procedure TCurl.SetProgressFunction(const AFunc: Curl_progress_callback);
begin
  FProgressFunction := AFunc;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PROGRESSFUNCTION, FuncPtr(@AFunc)),
    CURLOPT_PROGRESSFUNCTION);
end;

procedure TCurl.SetProgressData(AData: Pointer);
begin
  FProgressData := AData;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PROGRESSDATA, FProgressData), CURLOPT_PROGRESSDATA);
end;

{ ****** INFORMATION ****** }
function DoDebug(Handle: PCurl; Infotype: Curl_infotype; Data: PChar; Size: LongInt;
  PClient: Pointer): Longint; cdecl;
var
  BContinue: Boolean;
  I: LongInt;
  Info_str: PChar;
  Info_size: LongInt;
begin
  if (Handle <> nil) then { do nothing - compiler shut up! };
  BContinue := True;
  with TCurl(PClient) do
    if (@FOnDebug <> nil) then
    begin

      TCurl(PClient).MutexLock();
      if (InfoType = CURLINFO_TEXT) then
      begin
        Info_size := Size + 1;
        Info_str := StrAlloc(Info_size);
        FillChar(Info_str[0], Info_size, #0);
        for I := 0 to Size - 1 do
          if (Data[I] in [#13, #10]) then
          begin
            Info_str[I] := #0;
            Dec(Info_size);
          end
          else
            Info_str[I] := Data[I];
        if (StrLen(Info_str) > 0) then
          FOnDebug(TCurl(PClient), Infotype, Info_str, Info_size, BContinue);
        StrDispose(Info_str);
      end
      else
        FOnDebug(TCurl(PClient), Infotype, Data, Size, BContinue);
      TCurl(PClient).MutexUnlock();
    end;
  if BContinue then
    Result := 0
  else
    Result := -1;
end;

procedure TCurl.SetOnDebug(AProc: TCurlDebugEvent);
begin
  FOnDebug := AProc;
  if (FuncPtr(@AProc) <> nil) then
  begin
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_DEBUGFUNCTION, @DoDebug), CURLOPT_DEBUGFUNCTION);
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_DEBUGDATA, Self), CURLOPT_DEBUGDATA);
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_VERBOSE, LongInt(True)), CURLOPT_VERBOSE);
  end
  else
  begin
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_DEBUGFUNCTION, nil), CURLOPT_DEBUGFUNCTION);
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_VERBOSE, LongInt(False)), CURLOPT_VERBOSE);
  end;
end;

procedure TCurl.SetDebugFunction(AFunc: Curl_debug_callback);
begin
  FDebugFunction := AFunc;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_DEBUGFUNCTION, FuncPtr(@AFunc)),
    CURLOPT_DEBUGFUNCTION);
end;

procedure TCurl.SetDebugData(AData: Pointer);
begin
  FDebugData := AData;
  if (FuncPtr(@FOnDebug) <> nil) then
    SetOnDebug(nil);
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_DEBUGDATA, FDebugData), CURLOPT_DEBUGDATA);
end;

{ ****** SSLCTX ****** }

procedure TCurl.SetSslCtxFunction(Value: Curl_ssl_ctx_callback);
var
  Dummy: Pointer;
begin
  FSslCtxFunction := Value;
  SetPtrOption(CURLOPT_SSL_CTX_FUNCTION, Dummy, FuncPtr(@Value));
end;

procedure TCurl.SetSslCtxData(Value: Pointer);
begin
  SetPtrOption(CURLOPT_SSL_CTX_DATA, FSslCtxData, Value);
end;

{ ****** IOCTL ****** }

procedure TCurl.SetIoCtlCallback(Value: Curl_ioctl_callback);
var
  Dummy: Pointer;
begin
  FIoCtlCallback := Value;
  SetPtrOption(CURLOPT_IOCTLFUNCTION, Dummy, FuncPtr(@Value));
end;

procedure TCurl.SetIoCtlData(Value: Pointer);
begin
  SetPtrOption(CURLOPT_IOCTLDATA, FIoCtlData, Value);
end;

{ ****** ERROR ******* }

procedure TCurl.SetResultCode(ACode: CurlCode; AOption: CURLoption);
var
  StrOpt: string;
begin
  StrOpt := '';
  if (FCurlResult = CURLE_OK) and (ACode <> CURLE_OK) then
  begin
    FCurlResult := ACode;
    Str(LongInt(AOption), StrOpt);
    SetError(ACode, 'Error: ' + Curl_easy_strerror(ACode) + ' setting option #' + StrOpt);
  end;
end;

procedure TCurl.SetError(Code: CurlCode; const Msg: string);
begin
  FCurlResult := Code;
  StrLCopy(FErrorBuffer, PChar(Msg), CURL_ERROR_SIZE - 1);
end;

procedure TCurl.SetErrorFile(Value: string);
begin
  SetStringProp(FErrorFile, Value);
  FErrorStream := nil;
end;

procedure TCurl.SetErrorStream(Value: PIOFile);
begin
  SetStringProp(FErrorFile, '');
  SetPtrOption(CURLOPT_STDERR, Pointer(FErrorStream), Pointer(Value));
end;

procedure TCurl.InitErrorFile;
begin
  if (FErrorFile <> nil) then
  begin
    FErrorStream := Fopen(FErrorFile, 'w'#0);
    if (FErrorStream <> nil) then
      SetPtrOption(CURLOPT_STDERR, Pointer(FErrorStream), Pointer(FErrorStream))
    else
      SetError(CURLE_WRITE_ERROR, 'Error creating error log.');
  end;
end;

{ ****** COOKIE LIST ****** }

function DoListCookies(Sender: TObject; const Cookie: Ansistring; UserData: Pointer): Boolean;
begin
  Result := True;
  if (@TCurl(UserData).FOnListCookies <> nil) then
    TCurl(UserData).FOnListCookies(TObject(UserData), Cookie, Result)
  else
    Result := False;
end;

procedure TCurl.ListCookies;
begin
  if (FCookieList <> nil) and (@FOnListCookies <> nil) then
    FCookieList.ForEachCookie(@DoListCookies, Self);
end;

procedure TCurl.SetStringProp(var Field: PChar; const Value: string);
var
  Old_len, New_len: LongInt;
begin
  if (Field = nil) then
    Old_len := 0
  else
    Old_len := StrLen(Field);
  New_len := Length(Value);
  if (New_len = Old_len) and ((New_len = 0) or (StrLComp(PChar(Value), Field, New_len) = 0)) then
    EXIT;
  if (New_len = 0) or (Old_len < New_len) then
  begin
    StrDispose(Field);
    Field := nil;
  end
  else
    FillChar(Field[0], Old_len, #0);
  if (New_len > 0) then
  begin
    if (Field = nil) then
      Field := StrAlloc(New_len + 1);
    FillChar(Field[0], New_len + 1, #0);
    StrLCopy(Field, PChar(Value), New_len);
  end;
end;

function TCurl.SetListOption(Option: CurlOption; const AList: TCurlRWList): Boolean;
begin
  if (AList <> nil) then
  begin
    if (AList.FList <> nil) then
      SetResultCode(Curl_easy_setopt(FCurl, Option, AList.FList), Option);
    Result := (FCurlResult = CURLE_OK);
  end
  else
    Result := True;
end;

function TCurl.SetHttpPostOption: Boolean;
begin
  if (FHttpPost <> nil) then
    SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_HTTPPOST, FHttpPost), CURLOPT_HTTPPOST);
  Result := (FCurlResult = CURLE_OK);
end;

procedure TCurl.SetBoolOption(Option: CurlOption; out Field: Boolean; const Value: Boolean);
begin
  Field := Value;
  SetResultCode(Curl_easy_setopt(FCurl, Option, LongInt(Field)), Option);
end;

procedure TCurl.SetStrOption(Option: CurlOption; var Field: PChar; const Value: string);
begin
  SetStringProp(Field, Value);
  SetResultCode(Curl_easy_setopt(FCurl, Option, PChar(Field)), Option);
end;

procedure TCurl.SetIntOption(Option: CurlOption; out Field: Longint; const Value: Longint);
begin
  Field := Value;
  SetResultCode(Curl_easy_setopt(FCurl, Option, Field), Option);
end;

procedure TCurl.SetPtrOption(Option: CurlOption; out Field: Pointer; const Value: Pointer);
begin
  Field := Value;
  SetResultCode(Curl_easy_setopt(FCurl, Option, Value), Option);
end;

procedure TCurl.SetCrLf(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_CRLF, FCrLf, Value);
end;

procedure TCurl.SetVerbose(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_VERBOSE, FVerbose, Value);
end;

procedure TCurl.SetHeader(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_HEADER, FHeader, Value);
end;

procedure TCurl.SetNoProgress(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_NOPROGRESS, FNoProgress, Value);
end;

procedure TCurl.SetNoBody(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_NOBODY, FNoBody, Value);
end;

procedure TCurl.SetFailOnError(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FAILONERROR, FFailOnError, Value);
end;

procedure TCurl.SetUpload(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_UPLOAD, FUpload, Value);
end;

procedure TCurl.SetFtpListOnly(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FTPLISTONLY, FFtpListOnly, Value);
end;

procedure TCurl.SetFtpAppend(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FTPAPPEND, FFtpAppend, Value);
end;

procedure TCurl.SetFollowLocation(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FOLLOWLOCATION, FFollowLocation, Value);
end;

procedure TCurl.SetTransferText(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_TRANSFERTEXT, FTransferText, Value);
end;

procedure TCurl.SetHttpProxyTunnel(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_HTTPPROXYTUNNEL, FHttpProxyTunnel, Value);
end;

procedure TCurl.SetSslVerifyPeer(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_SSL_VERIFYPEER, FSslVerifyPeer, Value);
end;

procedure TCurl.SetFreshConnect(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FRESH_CONNECT, FFreshConnect, Value);
end;

procedure TCurl.SetForbidReuse(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FORBID_REUSE, FForbidReuse, Value);
end;

procedure TCurl.SetFtpUseEpsv(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FTP_USE_EPSV, FFtpUseEpsv, Value);
end;

procedure TCurl.SetFiletime(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FILETIME, FFiletime, Value);
end;

procedure TCurl.SetAutoReferer(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_AUTOREFERER, FAutoReferer, Value);
end;

procedure TCurl.SetPort(const Value: Word);
var
  Tmp: LongInt;
begin
  Tmp := Value;
  SetIntOption(CURLOPT_PORT, Tmp, LongInt(Value));
  FPort := WORD(Tmp);
end;

procedure TCurl.SetTimeout(const Value: LongInt);
begin
  SetIntOption(CURLOPT_TIMEOUT, FTimeout, Value);
end;

procedure TCurl.SetLowSpeedLimit(const Value: LongInt);
begin
  SetIntOption(CURLOPT_LOW_SPEED_LIMIT, FLowSpeedLimit, Value);
end;

procedure TCurl.SetLowSpeedTime(const Value: LongInt);
begin
  SetIntOption(CURLOPT_LOW_SPEED_TIME, FLowSpeedTime, Value);
end;

procedure TCurl.SetRange(const Value: string);
begin
  if (FResumeFrom <> 0) then
    SetResumeFrom(0);
  SetStrOption(CURLOPT_RANGE, FRange, Value);
end;

procedure TCurl.SetResumeFrom(const Value: LongInt);
begin
  if (FRange <> nil) then
    SetRange('');
  SetIntOption(CURLOPT_RESUME_FROM, FResumeFrom, Value);
end;

procedure TCurl.SetTimeValue(const Value: LongInt);
begin
  SetIntOption(CURLOPT_TIMEVALUE, FTimeValue, Value);
end;

procedure TCurl.SetProxyPort(const Value: LongInt);
begin
  SetIntOption(CURLOPT_PROXYPORT, FProxyPort, Value);
end;

procedure TCurl.SetMaxRedirs(const Value: LongInt);
begin
  SetIntOption(CURLOPT_MAXREDIRS, FMaxRedirs, Value);
end;

procedure TCurl.SetMaxConnects(const Value: LongInt);
begin
  SetIntOption(CURLOPT_MAXCONNECTS, FMaxConnects, Value);
end;

procedure TCurl.SetConnectTimeout(const Value: LongInt);
begin
  SetIntOption(CURLOPT_CONNECTTIMEOUT, FConnectTimeout, Value);
end;

procedure TCurl.SetUrl(const Value: string);
begin
  SetStrOption(CURLOPT_URL, FUrl, Value);
end;

procedure TCurl.SetProxy(const Value: string);
begin
  SetStrOption(CURLOPT_PROXY, FProxy, Value);
end;

procedure TCurl.SetUserPwd(const Value: string);
begin
  SetStrOption(CURLOPT_USERPWD, FUserPwd, Value);
end;

procedure TCurl.SetProxyUserPwd(const Value: string);
begin
  SetStrOption(CURLOPT_PROXYUSERPWD, FProxyUserPwd, Value);
end;

procedure TCurl.SetReferer(const Value: string);
begin
  SetStrOption(CURLOPT_REFERER, FReferer, Value);
end;

procedure TCurl.SetFtpPort(const Value: string);
begin
  SetStrOption(CURLOPT_FTPPORT, FFtpPort, Value);
end;

procedure TCurl.SetUserAgent(const Value: string);
begin
  SetStrOption(CURLOPT_USERAGENT, FUserAgent, Value);
end;

procedure TCurl.SetCookie(const Value: string);
begin
  SetStrOption(CURLOPT_COOKIE, FCookie, Value);
end;

procedure TCurl.SetSslCert(const Value: string);
begin
  SetStrOption(CURLOPT_SSLCERT, FSslCert, Value);
end;

procedure TCurl.SetSslCertPasswd(const Value: string);
begin
  SetStrOption(CURLOPT_SSLCERTPASSWD, FSslCertPasswd, Value);
end;

procedure TCurl.SetCustomRequest(const Value: string);
begin
  SetStrOption(CURLOPT_CUSTOMREQUEST, FCustomRequest, Value);
end;

procedure TCurl.SetInterface(const Value: string);
begin
  SetStrOption(CURLOPT_INTERFACE, FInterface, Value);
end;

procedure TCurl.SetKrb4Level(const Value: string);
begin
  SetStrOption(CURLOPT_KRB4LEVEL, FKrb4Level, Value);
end;

procedure TCurl.SetCaInfo(const Value: string);
begin
  SetStrOption(CURLOPT_CAINFO, FCaInfo, Value);
end;

procedure TCurl.SetRandomFile(const Value: string);
begin
  SetStrOption(CURLOPT_RANDOM_FILE, FRandomFile, Value);
end;

procedure TCurl.SetEgdSocket(const Value: string);
begin
  SetStrOption(CURLOPT_EGDSOCKET, FEgdSocket, Value);
end;

procedure TCurl.SetCookieJar(const Value: string);
begin
  SetStrOption(CURLOPT_COOKIEJAR, FCookieJar, Value);
end;

procedure TCurl.SetCookieFile(const Value: string);
begin
  FCookieList.Clear;
  if (Value <> '') and FileIsReadable(Value) then
    FCookieList.AddFromFile(Value);
  SetStrOption(CURLOPT_COOKIEFILE, FCookieFile, Value);
  if (FCookieJar = nil) then
    SetCookieJar(Value);
end;

procedure TCurl.SetSslCipherList(const Value: string);
begin
  SetStrOption(CURLOPT_SSL_CIPHER_LIST, FSslCipherList, Value);
end;

procedure TCurl.SetErrorBuffer(const Value: string);
begin
  SetStrOption(CURLOPT_ERRORBUFFER, FErrorBuffer, Value);
end;

procedure TCurl.SetWriteInfo(Value: string); // Not impemented in libcurl
begin
  SetStrOption(CURLOPT_WRITEINFO, FWriteInfo, Value);
end;

procedure TCurl.SetCookieSession(Value: Boolean);
begin
  SetBoolOption(CURLOPT_COOKIESESSION, FCookieSession, Value);
end;

procedure TCurl.SetCaPath(Value: string);
begin
  SetStrOption(CURLOPT_CAPATH, FCaPath, Value);
end;

procedure TCurl.SetDnsCacheTimeout(Value: LongInt);
begin
  // Sec's to store name resolves: default=60sec; Zero=disable; -1=forever;
  SetIntOption(CURLOPT_DNS_CACHE_TIMEOUT, FDnsCacheTimeout, Value);
end;

procedure TCurl.SetDnsUseGlobalCache(Value: Boolean);
begin
  SetBoolOption(CURLOPT_DNS_USE_GLOBAL_CACHE, FDnsUseGlobalCache, Value);
end;

procedure TCurl.SetNoSignal(Value: Boolean);
begin
  SetBoolOption(CURLOPT_NOSIGNAL, FNoSignal, Value);
end;

procedure TCurl.SetSslKey(Value: string);
begin
  SetStrOption(CURLOPT_SSLKEY, FSslKey, Value);
end;

procedure TCurl.SetSslEngine(Value: string);
begin
  SetStrOption(CURLOPT_SSLENGINE, FSslEngine, Value);
end;

procedure TCurl.SetSslEngineDefault(Value: Boolean);
begin
  SetBoolOption(CURLOPT_SSLENGINE_DEFAULT, FSslEngineDefault, Value);
end;

procedure TCurl.SetSslKeyPassword(Value: string);
begin
  SetStrOption(CURLOPT_SSLKEYPASSWD, FSslKeyPassword, Value);
end;

procedure TCurl.SetBufferSize(Value: LongInt);
begin
  SetIntOption(CURLOPT_BUFFERSIZE, FBufferSize, Value)
end;

procedure TCurl.SetHttpVersion(Value: Curl_http_version);
begin
  FHttpVersion := Value;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_HTTP_VERSION, LongInt(Value)),
    CURLOPT_HTTP_VERSION);
end;

procedure TCurl.SetClosePolicy(Value: Curl_closepolicy);
begin
  FClosePolicy := Value;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_CLOSEPOLICY, LongInt(Value)), CURLOPT_CLOSEPOLICY);
end;

procedure TCurl.SetTimeCondition(const Value: Curl_TimeCond);
begin
  FTimeCondition := Value;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_TIMECONDITION, LongInt(Value)),
    CURLOPT_TIMECONDITION);
end;

procedure TCurl.SetNetRc(const Value: CURL_NETRC_OPTION);
begin
  FNetrc := Value;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_NETRC, LongInt(Value)), CURLOPT_NETRC);
end;

procedure TCurl.SetSslVersion(const Value: Curl_sslversion);
begin
  FSslVersion := Value;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLVERSION, LongInt(Value)), CURLOPT_SSLVERSION);
end;

procedure TCurl.SetProxyType(Value: Curl_proxytype);
begin
  FProxyType := Value;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PROXYTYPE, LongInt(Value)), CURLOPT_PROXYTYPE);
end;

const
  STR_ENC_DEFLATE: PChar = 'deflate';
  STR_ENC_IDENTITY: PChar = 'identity';
  STR_CERT_PEM: PChar = 'PEM';
  STR_CERT_DER: PChar = 'DER';
  STR_CERT_ENG: PChar = 'ENG';

procedure TCurl.SetEncoding(Value: CurlEncoding);
begin
  FEncoding := Value;
  case Value of
    CURL_ENCODING_NONE:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_ENCODING, nil), CURLOPT_ENCODING);
    CURL_ENCODING_IDENTITY:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_ENCODING, @STR_ENC_DEFLATE[0]),
        CURLOPT_ENCODING);
    CURL_ENCODING_DEFLATE:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_ENCODING, @STR_ENC_IDENTITY[0]),
        CURLOPT_ENCODING);
    else
      SetResultCode(CURLE_BAD_CONTENT_ENCODING, CURLOPT_ENCODING);
  end;
end;

procedure TCurl.SetSslCertType(Value: CurlCertType);
begin
  FSslCertType := Value;
  case Value of
    CURL_CERT_NONE:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLCERTTYPE, nil), CURLOPT_SSLCERTTYPE);
    CURL_CERT_PEM:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLCERTTYPE, @STR_CERT_PEM[0]),
        CURLOPT_SSLCERTTYPE);
    CURL_CERT_DER:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLCERTTYPE, @STR_CERT_DER[0]),
        CURLOPT_SSLCERTTYPE);
    else
      SetResultCode(CURLE_SSL_CERTPROBLEM, CURLOPT_SSLCERTTYPE);
  end;
end;

procedure TCurl.SetSslKeyType(Value: CurlKeyType);
begin
  FSslKeyType := Value;
  case Value of
    CURL_KEY_NONE:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLKEYTYPE, nil), CURLOPT_SSLKEYTYPE);
    CURL_KEY_DER:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLKEYTYPE, @STR_CERT_DER[0]),
        CURLOPT_SSLKEYTYPE);
    CURL_KEY_ENG:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSLKEYTYPE, @STR_CERT_ENG[0]),
        CURLOPT_SSLKEYTYPE);
    else
      SetResultCode(CURLE_SSL_CERTPROBLEM, CURLOPT_SSLKEYTYPE);
  end;
end;

procedure TCurl.SetSslVerifyHost(Value: CurlHostVerify);
begin
  FSslVerifyHost := Value;
  case Value of
    CURL_VERIFY_NONE:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSL_VERIFYHOST, 0), CURLOPT_SSL_VERIFYHOST);
    CURL_VERIFY_EXIST:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSL_VERIFYHOST, 1), CURLOPT_SSL_VERIFYHOST);
    CURL_VERIFY_MATCH:
      SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_SSL_VERIFYHOST, 2), CURLOPT_SSL_VERIFYHOST);
    else
      SetResultCode(CURLE_SSL_CERTPROBLEM, CURLOPT_SSL_VERIFYHOST);
  end;
end;

procedure TCurl.SetPostFields(const Value: string);
begin
  SetBoolOption(CURLOPT_POST, FPost, True);
  if (FPostFields <> nil) then
  begin
    FreeMem(FPostFields);
    FPostFields := nil;
  end;
  SetIntOption(CURLOPT_POSTFIELDSIZE, FPostFieldSize, Length(Value));
  if (FPostFieldSize > 0) then
  begin
    GetMem(FPostFields, FPostFieldSize + 1);
    Move(Value[1], FPostFields[0], FPostFieldSize);
    FPostFields[FPostFieldSize] := #0;
  end;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_POSTFIELDS, FPostFields), CURLOPT_POSTFIELDS);
end;

procedure TCurl.SetHttpGet(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_HTTPGET, FHttpGet, Value);
end;

procedure TCurl.SetUnrestrictedAuth(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_UNRESTRICTED_AUTH, FUnrestrictedAuth, Value);
end;

procedure TCurl.SetFtpUseEPRT(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FTP_USE_EPRT, FFtpUseEPRT, Value);
end;

function AuthenticationsToInteger(Methods: CurlAuthenticationMethods): LongInt;
begin
  Result := CURLAUTH_NONE;
  if (AUTH_BASIC in Methods) then
    Result := Result or CURLAUTH_BASIC;
  if (AUTH_DIGEST in Methods) then
    Result := Result or CURLAUTH_DIGEST;
  if (AUTH_GSSNEGOTIATE in Methods) then
    Result := Result or CURLAUTH_GSSNEGOTIATE;
  if (AUTH_NTLM in Methods) then
    Result := Result or CURLAUTH_NTLM;
end;

procedure TCurl.SetHttpAuth(Value: CurlAuthenticationMethods);
var
  Dummy: LongInt;
begin
  FHttpAuth := Value;
  SetIntOption(CURLOPT_HTTPAUTH, Dummy, AuthenticationsToInteger(Value));
end;

procedure TCurl.SetProxyAuth(Value: CurlAuthenticationMethods);
var
  Dummy: LongInt;
begin
  FProxyAuth := Value;
  SetIntOption(CURLOPT_PROXYAUTH, Dummy, AuthenticationsToInteger(Value));
end;

procedure TCurl.SetIpResolve(Value: CurlResolverVersion);
var
  Dummy: LongInt;
begin
  FIPResolve := Value;
  SetIntOption(CURLOPT_IPRESOLVE, Dummy, LongInt(Value));
end;

procedure TCurl.SetFtpCreateMissingDirs(Value: Boolean);
begin
  SetBoolOption(CURLOPT_FTP_CREATE_MISSING_DIRS, FFtpCreateMissingDirs, Value);
end;

procedure TCurl.SetFtpResponseTimeout(Value: LongInt);
begin
  SetIntOption(CURLOPT_FTP_RESPONSE_TIMEOUT, FFtpResponseTimeout, Value);
end;

procedure TCurl.SetMaxFileSize(Value: LongInt);
begin
  SetIntOption(CURLOPT_MAXFILESIZE, FMaxFileSize, Value);
end;

procedure TCurl.SetCookieListOption;
begin
  if (COOKIES_LIB_STALE in FCookieList.FState) then
    FCookieList.SendListToLib;
end;

procedure TCurl.UpdateCookieList;
begin
  if not(COOKIES_LIB_STALE in FCookieList.FState) then
    FCookieList.FState := FCookieList.FState + [COOKIES_LIB_STALE];
end;

procedure TCurl.SetTcpNoDelay(Value: Boolean);
begin
  SetBoolOption(CURLOPT_TCP_NODELAY, FTcpNoDelay, Value);
end;

procedure TCurl.SetNetRcFile(Value: string);
begin
  SetStrOption(CURLOPT_NETRC_FILE, FNetRcFile, Value);
end;

procedure TCurl.SetFtpAccount(Value: string);
begin
  SetStrOption(CURLOPT_FTP_ACCOUNT, FFtpAccount, Value);
end;

procedure TCurl.SetSourceUserPwd(Value: string);
begin
  SetStrOption(CURLOPT_SOURCE_USERPWD, FSourceUserPwd, Value);
end;

procedure TCurl.SetSourceUrl(Value: string);
begin
  SetStrOption(CURLOPT_SOURCE_URL, FSourceUrl, Value);
end;

procedure TCurl.SetFtpSsl(Value: Curl_ftpssl);
var
  Dummy: LongInt;
begin
  FFtpSsl := Value;
  SetIntOption(CURLOPT_FTP_SSL, Dummy, LongInt(Value));
end;

procedure TCurl.SetFtpAuth(Value: Curl_ftpauth);
var
  Dummy: LongInt;
begin
  FFtpAuth := Value;
  SetIntOption(CURLOPT_FTPSSLAUTH, Dummy, LongInt(Value));
end;

procedure TCurl.SetIgnoreContentLength(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_IGNORE_CONTENT_LENGTH, FIgnoreContentLength, Value);
end;

procedure TCurl.SetPost(const Value: Boolean); // OBSOLETE, PostFields sets this, HttpGet unsets it.
begin
  SetBoolOption(CURLOPT_POST, FPost, Value);
end;

procedure TCurl.SetPut(const Value: Boolean); // OBSOLETE, use tCurl.Upload instead.
begin
  SetBoolOption(CURLOPT_PUT, FPut, Value);
end;

procedure TCurl.SetPostFieldSize(const Value: LongInt);
// OBSOLETE, PostFields sets this to Length(fPostFields)
begin
  SetIntOption(CURLOPT_POSTFIELDSIZE, FPostFieldSize, Value);
end;

procedure TCurl.SetFtpSkipPasvIp(const Value: Boolean);
begin
  SetBoolOption(CURLOPT_FTP_SKIP_PASV_IP, FFtpSkipPasvIp, Value);
end;

function GetStringProp(const Field: PChar): string;
begin
  if (Field <> nil) then
  begin
    Result := Field;
    UniqueString(Result);
  end
  else
    Result := '';
end;

function TCurl.GetUrl: string;
begin
  Result := GetStringProp(FUrl);
end;

function TCurl.GetProxy: string;
begin
  Result := GetStringProp(FProxy);
end;

function TCurl.GetUserPwd: string;
begin
  Result := GetStringProp(FUserPwd);
end;

function TCurl.GetProxyUserPwd: string;
begin
  Result := GetStringProp(FProxyUserPwd);
end;

function TCurl.GetRange: string;
begin
  Result := GetStringProp(FRange);
end;

function TCurl.GetPostFields: string;
begin
  Result := '';
  if (FPostFields <> nil) then
  begin
    SetLength(Result, FPostFieldSize);
    Move(FPostFields[0], Result[1], FPostFieldSize);
  end;
end;

function TCurl.GetReferer: string;
begin
  Result := GetStringProp(FReferer);
end;

function TCurl.GetFtpPort: string;
begin
  Result := GetStringProp(FFtpPort);
end;

function TCurl.GetUserAgent: string;
begin
  Result := GetStringProp(FUserAgent);
end;

function TCurl.GetCookie: string;
begin
  Result := GetStringProp(FCookie);
end;

function TCurl.GetSslCert: string;
begin
  Result := GetStringProp(FSslCert);
end;

function TCurl.GetSslCertPasswd: string;
begin
  Result := GetStringProp(FSslCertPasswd);
end;

function TCurl.GetCustomRequest: string;
begin
  Result := GetStringProp(FCustomRequest);
end;

function TCurl.GetInterface: string;
begin
  Result := GetStringProp(FInterface);
end;

function TCurl.GetKrb4Level: string;
begin
  Result := GetStringProp(FKrb4Level);
end;

function TCurl.GetCaInfo: string;
begin
  Result := GetStringProp(FCaInfo);
end;

function TCurl.GetRandomFile: string;
begin
  Result := GetStringProp(FRandomFile);
end;

function TCurl.GetEgdSocket: string;
begin
  Result := GetStringProp(FEgdSocket);
end;

function TCurl.GetCookieJar: string;
begin
  Result := GetStringProp(FCookieJar);
end;

function TCurl.GetCookieFile: string;
begin
  Result := GetStringProp(FCookieFile);
end;

function TCurl.GetSslCipherList: string;
begin
  Result := GetStringProp(FSslCipherList);
end;

function TCurl.GetErrorBuffer: string;
begin
  if (FErrorBuffer <> nil) and (FErrorBuffer[0] <> #0) then
    GetErrorBuffer := GetStringProp(FErrorBuffer)
  else
    case FCurlResult of
      CURLE_OK:
        GetErrorBuffer := 'success';
      CURLE_WRITE_ERROR:
        GetErrorBuffer := 'Error writing local file.';
      CURLE_READ_ERROR:
        GetErrorBuffer := 'Error reading local file.';
      else
        GetErrorBuffer := 'Unknown error.'; // <- I think this should never happen?
    end;
end;

function TCurl.GetCurlResult: CurlCode;
begin
  Result := FCurlResult;
  FCurlResult := CURLE_OK;
end;

function TCurl.GetWriteInfo: string; // Not implemented
begin
  Result := GetStringProp(FWriteInfo);
end;

function TCurl.GetCaPath: string;
begin
  Result := GetStringProp(FCaPath);
end;

function TCurl.GetSslEngine: string;
begin
  Result := GetStringProp(FSslEngine);
end;

function TCurl.GetSslKeyPassword: string;
begin
  Result := GetStringProp(FSslKeyPassword);
end;

function TCurl.GetSslKey: string;
begin
  Result := GetStringProp(FSslKey);
end;

function TCurl.GetHeaderFile: string;
begin
  Result := GetStringProp(FHeaderScheme.Filename);
end;

function TCurl.GetOutputFile: string;
begin
  Result := GetStringProp(FReceiveScheme.Filename);
end;

function TCurl.GetInputFile: string;
begin
  Result := GetStringProp(FTransmitScheme.Filename);
end;

function TCurl.GetErrorFile: string;
begin
  Result := GetStringProp(FErrorFile);
end;

function TCurl.GetReadFunction: Curl_read_callback;
begin
  Result := Curl_read_callback(FTransmitScheme.Callback);
end;

function TCurl.GetNetRcFile: string;
begin
  Result := GetStringProp(FNetRcFile)
end;

function TCurl.GetFtpAccount: string;
begin
  Result := GetStringProp(FFtpAccount);
end;

function TCurl.GetSourceUserPwd: string;
begin
  Result := GetStringProp(FSourceUserPwd);
end;

function TCurl.GetSourceUrl: string;
begin
  Result := GetStringProp(FSourceUrl);
end;

function RW_LIST_NOT_NIL(var O: TCurlRWList): TCurlRWList;
begin
  if (O = nil) then
    O := TCurlRWList.Create;
  Result := O;
end;

function TCurl.GetHttpHeader: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FHttpHdr);
end;

function TCurl.GetQuote: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FQuote);
end;

function TCurl.GetPostQuote: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FPostQuote);
end;

function TCurl.GetPreQuote: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FPreQuote);
end;

function TCurl.GetTelnetOptions: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FTelnetOptions);
end;

function TCurl.GetHttp200Aliases: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FHttp200Aliases);
end;

function TCurl.GetSourcePreQuote: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FSourcePreQuote);
end;

function TCurl.GetSourceQuote: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FSourceQuote);
end;

function TCurl.GetSourcePostQuote: TCurlRWList;
begin
  Result := RW_LIST_NOT_NIL(FSourcePostQuote);
end;

procedure TCurl.InitFields();
begin
  FCrLf := False;
  FVerbose := False;
  FHeader := False;
  FNoProgress := True;
  FNoBody := False;
  FFailOnError := False;
  FUpload := False;
  FPost := False;
  FFtpListOnly := False;
  FFtpAppend := False;

  FTransferText := False;
  FPut := False;
  FHttpProxyTunnel := False;
  FSslVerifyPeer := True;
  FFreshConnect := False;
  FForbidReuse := False;
  FHttpGet := False;
  FFtpUseEpsv := True;
  FFiletime := False;
  FFtpAscii := False;
  FUpload := False;
  FPut := False;
  FCookieSession := False;
  FDnsUseGlobalCache := False;
  FNoSignal := False;
  FSslEngineDefault := False;
  FUnrestrictedAuth := False;
  FFtpUseEPRT := False;

  FPort := 0;
  FTimeout := 0;
  FLowSpeedLimit := 0;
  FLowSpeedTime := 0;
  FResumeFrom := 0;
  FTimeValue := 0;
  FProxyPort := 0;
  FPostFieldSize := 0;
  FMaxConnects := 5;
  FConnectTimeout := 0;
  FResumeFrom := 0;
  FInfileSize := -1;
  FDnsCacheTimeout := 60;
  FBufferSize := 0; // ???

  FUrl := nil;
  FProxy := nil;
  FUserPwd := nil;
  FProxyUserPwd := nil;
  FRange := nil;
  FErrorBuffer := nil;
  FPostFields := nil;
  FReferer := nil;
  FFtpPort := nil;
  FUserAgent := nil;
  FCookie := nil;
  FSslCert := nil;
  FSslCertPasswd := nil;
  FCustomRequest := nil;
  FInterface := nil;
  FKrb4Level := nil;

  FRandomFile := nil;
  FEgdSocket := nil;

  FSslCipherList := nil;
  FWriteInfo := nil;

  FSslEngine := nil;
  FSslKeyPassword := nil;
  FErrorFile := nil;

  FNetrc := CURL_NETRC_LAST;
  FSslVersion := CURL_SSLVERSION_DEFAULT;
  FTimeCondition := CURL_TIMECOND_NONE;
  FHttpVersion := CURL_HTTP_VERSION_1_1;
  FClosePolicy := CURLCLOSEPOLICY_NONE;
  FProxyType := CURLPROXY_HTTP;
  FEncoding := CURL_ENCODING_NONE;
  FSslCertType := CURL_CERT_NONE;
  FSslKeyType := CURL_KEY_NONE;
  FSslVerifyHost := CURL_VERIFY_NONE;

  FOnProgress := nil;
  FOnDebug := nil;
  FOnListCookies := nil;
  FErrorStream := nil;

  with FHeaderScheme do
  begin
    Hdr_event := nil;
    Stream := nil;
    Filename := nil;
    Cb_type := CBT_INTERNAL;
    Fs_type := FST_INTERNAL;
  end;

  with FReceiveScheme do
  begin
    Rx_event := nil;
    Stream := nil;
    Filename := nil;
    Cb_type := CBT_INTERNAL;
    Fs_type := FST_INTERNAL;
  end;

  with FTransmitScheme do
  begin
    Tx_event := nil;
    Stream := nil;
    Filename := nil;
    Cb_type := CBT_INTERNAL;
    Fs_type := FST_INTERNAL;
  end;

  FCookieJar := nil;
  FCookieFile := nil;

  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_COOKIEFILE, PChar(#0#0)), CURLOPT_COOKIEFILE);

  FPrivateData := nil;
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_PRIVATE, Self), CURLOPT_PRIVATE);

  FHttpAuth := [AUTH_BASIC];
  FProxyAuth := [AUTH_BASIC];
  FFtpCreateMissingDirs := False;
  FFtpResponseTimeout := 0;
  FIpResolve := CURL_IPRESOLVE_WHATEVER;
  FMaxFileSize := 0;
  FSslCtxData := nil;
  FSslCtxFunction := nil;

  FErrorBuffer := StrAlloc(CURL_ERROR_SIZE);
  FillChar(FErrorBuffer[0], CURL_ERROR_SIZE, #0);
  SetResultCode(Curl_easy_setopt(FCurl, CURLOPT_ERRORBUFFER, @FErrorBuffer[0]),
    CURLOPT_ERRORBUFFER);

  FHttpHdr := nil;
  FTelnetOptions := nil;
  FHttp200Aliases := nil;
  FPreQuote := nil;
  FQuote := nil;
  FPostQuote := nil;
  FSourcePreQuote := nil;
  FSourceQuote := nil;
  FSourcePostQuote := nil;

  FFormData := TMultiPartFormData.Create;
  FSslEnginesList := TCurlROList.Create;
  UpdateSslEnginesList;
  FIoCtlCallback := nil;
  FIoCtlData := nil;
  FTcpNoDelay := False;
  FNetRcFile := nil;
  FFtpAccount := nil;

  FSourceUserPwd := nil;
  FSourceUrl := nil;
  FFtpSsl := CURLFTPSSL_NONE;
  FFtpAuth := CURLFTPAUTH_DEFAULT;
  FIgnoreContentLength := False;

  // fFollowLocation:=False;
  SetBoolOption(CURLOPT_FOLLOWLOCATION, FFollowLocation, True);
  // fAutoReferer:=False;
  SetBoolOption(CURLOPT_AUTOREFERER, FAutoReferer, True);
  // fMaxRedirs:=0;
  SetIntOption(CURLOPT_MAXREDIRS, FMaxRedirs, 25);

  if (DEFAULT_WIN32_CA_CERT <> '') then
  begin
    SetStrOption(CURLOPT_CAINFO, FCaInfo, DEFAULT_WIN32_CA_CERT);
  end
  else
    FCaInfo := nil;

  if (DEFAULT_WIN32_CA_PATH <> '') then
  begin
    SetStrOption(CURLOPT_CAPATH, FCaPath, DEFAULT_WIN32_CA_PATH);
  end
  else
    FCaPath := nil;

  FThdResult := FCurlResult;
  FFtpSkipPasvIp := False;
end;

procedure TCurl.Release;
begin
  if (FHttpHdr <> nil) then
    FHttpHdr.Free;
  if (FQuote <> nil) then
    FQuote.Free;
  if (FPostQuote <> nil) then
    FPostQuote.Free;
  if (FPreQuote <> nil) then
    FPreQuote.Free;
  if (FFormData <> nil) then
    FFormData.Free;
  if (FTelnetOptions <> nil) then
    FTelnetOptions.Free;
  if (FHttp200Aliases <> nil) then
    FHttp200Aliases.Free;
  with FHeaderScheme do
    if (Filename <> nil) then
      StrDispose(Filename);
  with FReceiveScheme do
    if (Filename <> nil) then
      StrDispose(Filename);
  with FTransmitScheme do
    if (Filename <> nil) then
      StrDispose(Filename);
  if (FUrl <> nil) then
    StrDispose(FUrl);
  if (FProxy <> nil) then
    StrDispose(FProxy);
  if (FUserPwd <> nil) then
    StrDispose(FUserPwd);
  if (FProxyUserPwd <> nil) then
    StrDispose(FProxyUserPwd);
  if (FRange <> nil) then
    StrDispose(FRange);
  if (FPostFields <> nil) then
    FreeMem(FPostFields);
  if (FReferer <> nil) then
    StrDispose(FReferer);
  if (FFtpPort <> nil) then
    StrDispose(FFtpPort);
  if (FUserAgent <> nil) then
    StrDispose(FUserAgent);
  if (FCookie <> nil) then
    StrDispose(FCookie);
  if (FSslCert <> nil) then
    StrDispose(FSslCert);
  if (FSslCertPasswd <> nil) then
    StrDispose(FSslCertPasswd);
  if (FCustomRequest <> nil) then
    StrDispose(FCustomRequest);
  if (FInterface <> nil) then
    StrDispose(FInterface);
  if (FKrb4Level <> nil) then
    StrDispose(FKrb4Level);
  if (FCaInfo <> nil) then
    StrDispose(FCaInfo);
  if (FRandomFile <> nil) then
    StrDispose(FRandomFile);
  if (FEgdSocket <> nil) then
    StrDispose(FEgdSocket);
  // if ( fCookieJar      <> nil ) then StrDispose( fCookieJar );
  // if ( fCookieFile     <> nil ) then StrDispose( fCookieFile );
  if (FSslCipherList <> nil) then
    StrDispose(FSslCipherList);
  if (FWriteInfo <> nil) then
    StrDispose(FWriteInfo);
  if (FCaPath <> nil) then
    StrDispose(FCaPath);
  if (FSslKey <> nil) then
    StrDispose(FSslKey);
  if (FSslEngine <> nil) then
    StrDispose(FSslEngine);
  if (FSslKeyPassword <> nil) then
    StrDispose(FSslKeyPassword);
  if (FErrorBuffer <> nil) then
    StrDispose(FErrorBuffer);
  if (FErrorFile <> nil) then
    StrDispose(FErrorFile);

  if (FSslEnginesList <> nil) then
    FSslEnginesList.Free;
  if (FNetRcFile <> nil) then
    StrDispose(FNetRcFile);
  if (FFtpAccount <> nil) then
    StrDispose(FFtpAccount);

  if (FSourcePreQuote <> nil) then
    FSourcePreQuote.Free;
  if (FSourceQuote <> nil) then
    FSourceQuote.Free;
  if (FSourcePostQuote <> nil) then
    FSourcePostQuote.Free;
  if (FSourceUserPwd <> nil) then
    StrDispose(FSourceUserPwd);
  if (FSourceUrl <> nil) then
    StrDispose(FSourceUrl);

end;

constructor TComponent.Create(AOwner: TComponent);
begin
  inherited Create;
  FOwner := AOwner;
  FTag := 0;
end;

constructor TCurl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCurl := Curl_easy_init;
  if (FCurl = nil) then
  begin
    FCurlResult := CURLE_FAILED_INIT;
    Self.Destroy;
    Self := nil;
    Abort; // FAIL; // Ruzzz
  end
  else
    FCurlResult := CURLE_OK;
  InitFields();
  FCookieList := TCurlCookieList.Create(Self);
  FMultiNotifyDestroying := nil;
  FMulti := nil;
  FPrev := nil;
  FNext := nil;
end;

destructor TCurl.Destroy;
begin
  if (@FMultiNotifyDestroying <> nil) then
    FMultiNotifyDestroying(Self);
  if (FCookieList <> nil) then
    FCookieList.Free;
  if (FCurl <> nil) then
    Curl_easy_cleanup(FCurl);
  Release;
  inherited Destroy;
end;

function TCurl.Perform: Boolean;
begin
  InitTransfer;
  if (FCurlResult = CURLE_OK) then
  begin
    FCurlResult := DoPerform(FCurl);
  end;
  Result := (FCurlResult = CURLE_OK);
  DoneTransfer(FCurlResult);
end;

procedure TCurl.Clear;
begin
  if (COOKIES_OBJ_STALE in FCookieList.FState) then
    FCookieList.SendListToLib;
  Curl_easy_reset(FCurl);
  Release();
  InitFields();
end;

class function TCurl.Escape(const S: string): string;
var
  Tmp: PChar;
begin
  Tmp := Curl_escape(PChar(S), Length(S));
  Result := Tmp;
  UniqueString(Result);
  Curl_free(Tmp);
end;

class function TCurl.Unescape(const S: string): string;
var
  Tmp: PChar;
begin
  Tmp := Curl_unescape(PChar(S), Length(S));
  Result := Tmp;
  UniqueString(Result);
  Curl_free(Tmp);
end;

procedure InitWin32CACert;
var
  Buflen: DWORD;
  Buf: PChar;
  P: PChar;
begin
  if TCurl.Features.Ssl then
  begin
    GetMem(Buf, MAX_PATH + 1);
    FillChar(Buf^, MAX_PATH + 1, #0);
    Buflen := SearchPath(nil, 'curl-ca-bundle.crt', nil, MAX_PATH + 2, Buf, {$IFDEF FPC}@{$ENDIF}P);
    if (Buflen > 0) then
    begin
      DEFAULT_WIN32_CA_CERT := Buf;
      UniqueString(DEFAULT_WIN32_CA_CERT);
      if (P <> nil) then
      begin
        P[0] := #0;
        DEFAULT_WIN32_CA_PATH := Buf;
        UniqueString(DEFAULT_WIN32_CA_PATH);
      end;
    end;
    FreeMem(Buf);
  end;
end;

constructor TCurlBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBusy := False;
  FThreaded := False;
  FWaitInterval := 1000;
  FWaitCallback := nil;
  FOnWait := nil;
  FWaitData := nil;
end;

procedure TCurlBase.SetOnWait(AEvent: TNotifyEvent);
begin
  FWaitCallback := nil;
  FOnWait := AEvent;
end;

procedure TCurlBase.SetWaitCallback(ACallback: TCurlWaitCallback);
begin
  FOnWait := nil;
  FWaitCallback := ACallback;
end;

procedure TCurlBase.SetWaitInterval(Ms: Longint);
begin
  if (Ms >= 0) then
    FWaitInterval := Ms
  else
    FWaitInterval := 1000;
end;

procedure CurlThreadExecute(O: Pointer); cdecl;
begin
  with TCurl(O) do
  begin
    FThdResult := Curl_easy_perform(FCurl);
    FBusy := False;
  end;
  _endthread();
end;

function TCurl.DoPerform(ACurl: PCurl): CurlCode;
const
  ERR_MSG = 'TODO'; // TODO: ERR_MSG

begin
  if FThreaded then
  begin
    if (FBusy) then
    begin
      Result := CURLE_COULDNT_CONNECT;
      SetError(Result, ERR_MSG);

      EXIT;
    end;
    FThdResult := FCurlResult;
    FBusy := True;

    FThread := _beginthread(@CurlThreadExecute, 0, Self);
    while (FBusy) do
    begin
      Windows.Sleep(FWaitInterval);
      if Assigned(FOnWait) and (@FOnWait <> nil) then
        FOnWait(Self)
      else if Assigned(FWaitCallback) and (@FWaitCallback <> nil) then
        FWaitCallback(FWaitData);
    end;
    CloseHandle(FThread);

    Result := FThdResult;
  end
  else
  begin
    FBusy := True;
    Result := Curl_easy_perform(ACurl);
    FBusy := False;
  end;
end;

procedure TCurl.MutexLock;
begin

end;

procedure TCurl.MutexUnlock;
begin

end;

function TCurl.InitTransfer: CurlCode;
begin
  SetListOption(CURLOPT_HTTPHEADER, FHttpHdr);
  SetListOption(CURLOPT_QUOTE, FQuote);
  SetListOption(CURLOPT_POSTQUOTE, FPostQuote);
  SetListOption(CURLOPT_PREQUOTE, FPreQuote);
  SetListOption(CURLOPT_TELNETOPTIONS, FTelnetOptions);
  SetListOption(CURLOPT_HTTP200ALIASES, FHttp200Aliases);
  SetListOption(CURLOPT_SOURCE_QUOTE, FSourceQuote);
  SetListOption(CURLOPT_SOURCE_POSTQUOTE, FSourcePostQuote);
  SetListOption(CURLOPT_SOURCE_PREQUOTE, FSourcePreQuote);
  SetCookieListOption;
  if (FFormData <> nil) and (FFormData.PostPtr <> nil) then
  begin
    case FFormData.Result of
      CURLE_OK:
        FHttpPost := FFormData.PostPtr;
      CURLE_READ_ERROR:
        SetError(CURLE_READ_ERROR, 'Unable to open POST input file');
      else
        FCurlResult := FFormData.Result;
    end;
  end;
  SetHttpPostOption;
  if (FUpload or FPut) then
    InitInputFile
  else
    InitOutputFile;
  InitHeaderFile;
  InitErrorFile;
  if (FUrl = nil) or (FUrl^ = #0) then
    SetError(CURLE_URL_MALFORMAT, 'NULL or empty URL.');
  Result := FCurlResult;
end;

procedure TCurl.DoneTransfer(ACode: CurlCode);
var
  TmpCode: CurlCode;
begin
  TmpCode := CURLE_OK;

  with FReceiveScheme do
    if (Fs_type = FST_FILENAME) and (Stream <> nil) then
    begin
      if (Fclose(Stream) <> 0) then
        TmpCode := CURLE_WRITE_ERROR;
      Stream := nil;
    end;

  with FHeaderScheme do
  begin
    if ((Fs_type = FST_FILENAME) and (Stream <> nil)) or
      ((Fs_type = FST_INTERNAL) and (not(FNoBody or FHeader)) and (Stream <> nil)) then
    begin
      if (Fclose(Stream) <> 0) then
        TmpCode := CURLE_WRITE_ERROR;
      Stream := nil;
    end;
  end;

  with FTransmitScheme do
    if (Fs_type = FST_FILENAME) and (Stream <> nil) then
    begin
      if (Fclose(Stream) <> 0) then
        TmpCode := CURLE_READ_ERROR;
      Stream := nil;
    end;

  if (FErrorStream <> nil) and (FErrorFile <> nil) then
  begin
    if (Fclose(FErrorStream) <> 0) then
      TmpCode := CURLE_WRITE_ERROR;
    FErrorStream := nil;
  end;

  if (ACode = CURLE_OK) and (TmpCode <> CURLE_OK) then
    FCurlResult := TmpCode
  else if (FCurlResult <> ACode) then
    FCurlResult := ACode;

  UpdateCookieList;
end;

initialization

Curl_global_init(CURL_GLOBAL_ALL);
GlobalProtocolList := InitProtocolList;
GlobalVersionInfoData := Curl_version_info(CURLVERSION_NOW)^;
InitFeatures;
InitWin32CACert();

finalization

GlobalProtocolList.Free;
Curl_global_cleanup;

end.
