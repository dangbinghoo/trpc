module trpc.client;

import trpc.ifinfo;
import asdf;
import std.experimental.logger : log;

/// TODO _rpc_id should be mutex protected.
__gshared long _rpc_id = 1; 
long getJsonRPCID() {
	return _rpc_id++;
}

/// mixin a single method, seprate this makes code a bit more clear
/// rpcSendReqFuncname is:  string funcname (string req, int timeout);
string _mixinSingleFunc(MethodInfo info, string rpcSendReqFuncname, int timeout) {
	import std.array : join;
	import std.conv : to;
	/// function signature
	string r = "";
	r ~= `//// RPC-Method [` ~ info.name ~ `]
	` ~ info.rettype ~ " " ~ info.name ~ "(";
	// params
	string[] _params = new string[info.params.length];
	foreach (i, p; info.params) {
		if ((p.storetype == "out") || (p.storetype == "ref")) {
			_params[i] ~= p.storetype ~ " " ~ p.type ~ " " ~ p.name;
		}
		else {
			_params[i] ~= p.type ~ " " ~ p.name;
		}
	}
	r ~= _params.join(", ");
	r ~=  `) {
		import std.experimental.logger : log, LogLevel;
		immutable _rpcName = "` ~ info.name ~ `";
		` ~ info.rettype ~ ` _ret;`;
	// function scope erea.
	///
	/// now serialize all params and function name, return to a rpc call string or blob.
	///
	import std.algorithm : map;
	import std.conv: to;
	import std.array : array;
	string[] _outparams; string[] _inparams; string[] _outparam_names;
	foreach (i, p; info.params) {
		if (p.storetype == "out") {
			_outparams ~= p.type ~ " " ~ p.name;
			_outparam_names ~= p.name;
		}
		else {
			_inparams ~= p.type ~ " " ~ p.name;
		}
	}
	// in params outline
	r ~= ` struct _InParams {` ~  _inparams.map!(a => a ~ "; ").join ~ `}`;
	r ~= `
		_InParams _inprm;
	`;
	foreach (i, p; info.params) {
		if (p.storetype != "out") {
			r ~= `_inprm.` ~ p.name ~ `= ` ~ p.name ~ `;`;
		}
	}
	r ~= `
		struct Jrpc2Req {
			string method;
			long id;
			_InParams params;
		}
	`;
	r ~= `Jrpc2Req _req; _req.id = getJsonRPCID(); ` ~ `_req.method = _rpcName;
	`;
	r ~= `_req.params = _inprm;`;


	/// REQUEST
	r ~= `
		string respstr = ` ~ rpcSendReqFuncname ~ `(serializeToJson(_req), ` ~ to!string(timeout) ~ `);`;

	/// out-param
	r ~= `
	struct _OutParams {` ~ info.rettype ~ ` ret; ` ~ _outparams.map!(a => a ~ "; ").join ~ `}`;
	r ~= `
		struct Jrpc2Responce {
			string method;
			long id;
			int status;
			string errinfo;
			_OutParams result;
		}
	`;

	/// Get RESPONCE and Parse.
	r ~= `
		try {
			Jrpc2Responce _resp = respstr.deserialize!Jrpc2Responce;
			if (_resp.method != _rpcName) {
				log(LogLevel.error, "Ooops! Json method not match! calling <", _rpcName, ">, 
					got (", _resp.method ,").");
			}
			else {
				_ret = _resp.result.ret;`;

	// re-assign out storage type params
	foreach(n; _outparam_names) {
		r ~= " " ~ n ~ ` = _resp.result.` ~ n ~ ";";
	}

	r ~= 
	` 
			}
		} catch (Exception e) {
			log(LogLevel.critical, "Err: Json responce parse error !");
		}`;

	r ~=  `
	return _ret;
	}`;
	return r;
}

/// mixin method body using Interface meta-info.
string[] mixinFuncStr(string ifModuleName, MethodInfo[] ifInfos, string rpcSendReqFuncname, int timeout) {
    string[] _mtdstrs = new string[ifInfos.length];
    import std.array : join;
    
    foreach (i, MethodInfo _info; ifInfos) {
        if (_info._customtypes.length > 0) {
            _mtdstrs[i] = `import ` ~ ifModuleName ~ `: ` ~ _info._customtypes.join(", ") ~ `;
        ` ~ _mixinSingleFunc(_info, rpcSendReqFuncname, timeout);
        }
        else {
            _mtdstrs[i] = _mixinSingleFunc(_info, rpcSendReqFuncname, timeout);
        }
    }

    return _mtdstrs;
}


private struct CustomTypes {
    string[] list;
}

/// Auto Implement method for a given interface.
class ImplIfToRpc(I, int TimeoutMs) 
	{
    import std.traits: moduleName;

    /// TODO: "working" workaround for importing identifieres related to I.
    ///       need to find a more-elegant-way
    enum _ifModuleName = moduleName!I;

    /// interface meta info
    enum _ifinfos = IfInfo!I().getInfos();


    /// mixin method body
    enum _SerFunStr = mixinFuncStr(_ifModuleName, _ifinfos, "rpcRequest", TimeoutMs);

    ///
    this() {
        
    }

	string rpcRequest(string req, int timeout) {
		return "";
	}

    static foreach (_str; _SerFunStr) {
        //pragma(msg, _str);
        mixin(_str);
    }
}

/// Thread RPC client
class ThrdRPClient(I, int T) : ImplIfToRpc!(I, T) {
	import std.concurrency : Tid, send, receiveTimeout;
	import core.thread: msecs;

	private Tid _srvThrdId;

	/// 
	this(Tid srvThrdId) {
		this._srvThrdId = srvThrdId;
	}

	override string rpcRequest(string req, int timeout) {
		this._srvThrdId.send(req);
		string _resp;
		const bool _received = receiveTimeout(msecs(timeout), (string x) {
			_resp = x;
		});

		if (_received) {
			return _resp;
		}

		return "";
	}
}

/// Thread RPC client
class ThrdRPCTcpClient(I, int T) : ImplIfToRpc!(I, T) {
	import std.socket : TcpSocket;
	import core.thread: msecs;
	import std.conv : to;

	private TcpSocket _tcpsock;
	private size_t _max_rcv_len;

	/// 
	this(TcpSocket tcpsock, size_t max_rcv_len) {
		this._tcpsock = tcpsock;
		this._max_rcv_len = max_rcv_len;
	}

	override string rpcRequest(string req, int timeout) {
		ubyte[] recv_data = new ubyte[this._max_rcv_len];
		size_t len;
		string _resp = "";
		try {
			version (LogRPCInfo) {
				log("sending .. <", req, ">...");
			}
			_tcpsock.send(req);
			version (LogRPCInfo) {
				log("waiting rpc server reply...");
			}
			int tries = timeout / 100;
			if (_tcpsock.blocking) {
				len = _tcpsock.receive(recv_data);
			}
			else {
				while (tries--) {
					len = _tcpsock.receive(recv_data);
					if (len > 0)
						break;
				}
				if (tries <= 0) {
					log("Request timed out!");
				}
			}

			if (len > 0) {
				_resp = to!string(cast(char[])recv_data[0 .. len]);
				version (LogRPCInfo) {
					log("got rply : ", _resp);
				}
			}
		}
		catch (Exception e) {
			log(e.msg);
		}
		
		return _resp;
	}
}
