module trpc.server;

import trpc.ifinfo;
import asdf;
import std.json;

import std.experimental.logger : log, LogLevel;

private string _mixinDispatchCases(MethodInfo[] ifInfos) {
	string s = "";
	foreach (m; ifInfos) {
		s ~= `
			case "` ~ m.name ~ `":` ~ `
				ret = _disp_` ~ m.name ~ `(params, resp);
				break;`;
	}

	return s ~ `
			default:  ret = -1;`;
}

private struct ParamS {
	string type;
	string name;
}

private string _mixinDispatchMethod(MethodInfo info, string srvclass_name) {
	import std.array : join;
	ParamS[] _inParams, _outParams;
	string r;
	r ~= `//// RPC-Srv-Method [` ~ info.name ~ `]
	` ~ "int _disp_" ~ info.name ~ ` (JSONValue params, out string resp) {
		bool _parse_ok = false;
		`;

	foreach (i, p; info.params) {
		if (p.storetype == "out") {
			_outParams ~= ParamS(p.type, p.name);
		}
		else {
			_inParams ~= ParamS(p.type, p.name);
		}
	}
	// in-param
	r ~= `struct _InParams { `;
	foreach (p; _inParams) {
		r ~= p.type ~ " " ~ p.name ~ "; ";
	}
	r ~= `}`;
	// out-param
	r ~= ` struct _OutParams {`;
	foreach (p; _outParams) {
		r ~= p.type ~ " " ~ p.name ~ "; ";
	}
	r ~= info.rettype ~ ` ret; } _OutParams _outp;`;

	// deserial-in-param
	r ~= ` _InParams _inp; ` ~ info.rettype ~ ` ret; 
		try {
			_inp = deserialize!_InParams(params.toString);`;

	r ~= `
			ret = ` ~ srvclass_name ~ `.` ~ info.name ~ `(`;
	string [] _pnames;
	foreach (ap; info.params) {
		if ((ap.storetype == "none") || (ap.storetype == "ref"))
			_pnames ~= `_inp.` ~ ap.name;
		if (ap.storetype == "out")
			_pnames ~= `_outp.` ~ ap.name;
	}
	r ~= _pnames.join(", ") ~ `);`;

	// out param assignment.
	r ~= `
			_outp.ret = ret;`;

	r ~= `
			_parse_ok = true;
		} catch (Exception e) {
			_parse_ok = false;
			log("Error, deserialize In-Param of method error!");
		}
		`;

	//
	r ~= `
		if (_parse_ok) {
			try {
				resp = serializeToJson(_outp);
				log("Responce json is : ", resp);
			}
			catch (Exception e) {
				_parse_ok = false;
				log(e.msg);
			}
		}

		if (_parse_ok) {
			return 0;
		}

		return -1;
	}`;

	return r;
}

///
class ImplRpcSrvOfIf(C) {
	
	import std.traits : moduleName;
    import std.array : join;

    /// TODO: "working" workaround for importing identifieres related to I.
    ///       need to find a more-elegant-way
    enum _ifModuleName = moduleName!C;

    /// interface meta info
    enum _minfos = IfInfo!C().getInfos();

	//pragma(msg, "_ifinfos of Class: ", _minfos);

	private  C _srvclass;

	///
	enum _srvclass_name = __traits(identifier, _srvclass);

	///
	this(ref C srvclass) {
		_srvclass = srvclass;
	}

	/// mixin dispatch method.
	static foreach (m; _minfos) {
		//pragma(msg, _mixinDispatchMethod(m, _srvclass_name));
        static if (m._customtypes.length > 0) {
            mixin(`import ` ~ _ifModuleName ~ `: ` ~ m._customtypes.join(", ") ~ `;
                ` ~ _mixinDispatchMethod(m, _srvclass_name));
        }
        else {
            mixin(_mixinDispatchMethod(m, _srvclass_name));
        }
	}

	private int _dispatch(string method, JSONValue params, out string resp) {
		mixin(`int ret = 0;`);
		immutable string _case = _mixinDispatchCases(_minfos);
		//pragma(msg, _case);
		switch (method) {
			mixin(_case);
		}
		return ret;
	}

	/// execute rpc request
	int executeMethod(string req, out string resp) {
		log("req is ", req);
		long id; string method; JSONValue params;
		JSONValue reqjson; string respjs;
		int ret = 0;
		try {
			reqjson = parseJSON(req);
			id = reqjson["id"].integer;
			method = reqjson["method"].str;
			params = reqjson["params"].object;
			ret = this._dispatch(method, params, respjs);
		}
		catch (Exception e) {
			log(e.msg);
		}

		JSONValue respjobj;
		try {
			respjobj["method"] = JSONValue(method);
			respjobj["id"] = JSONValue(id);
			respjobj["status"] = JSONValue(ret);
		}
		catch (Exception e) {
			log(e.msg);
		}
		
		respjobj["result"] = parseJSON(respjs);
		if (ret == 0) {
			respjobj["errinfo"] = "";
		}
		else {
			respjobj["errinfo"] = "Json rpc request failed!";
		}

		resp = respjobj.toString;
		log("Method retured Json-Str: ", resp);
		return ret;
	}
}

import std.concurrency : spawn, Tid, receiveOnly, send, ownerTid;

/// Thread-RPC method excute and responce deals
void thrdRPCSrvProcess (C) (ImplRpcSrvOfIf!C srvcls) {
    import std.concurrency : Tid, receiveOnly, send, ownerTid;
    auto recv = receiveOnly!string();
    string resp;
    srvcls.executeMethod(recv, resp);
    ownerTid.send(resp);
}

/// Thread-RPC method excute and responce deals - None-block
void thrdRPCSrvProcessNoneBlock (C) (ImplRpcSrvOfIf!C srvcls, int timeout_ms) {
    import std.concurrency : Tid, receiveTimeout, send, ownerTid;
    import core.thread : msecs;
    string recv, resp;
    const bool _received = receiveTimeout(msecs(timeout_ms), (string req) {
                                                        recv = req;
                                                        });
    if (_received) {
        srvcls.executeMethod(recv, resp);
        ownerTid.send(resp);
    }
}

/// simple standard Thread RPC server
mixin template thrdRPCSrvThreadTemplate(alias C, alias CtorCall) {
    void thrdRPCSrvThread() {
        import core.thread : msecs, Thread;
        auto _srvimpl = CtorCall;
        auto srvcls = new ImplRpcSrvOfIf!C(_srvimpl);

        while (true) {
            thrdRPCSrvProcess!C(srvcls);
            Thread.sleep(msecs(100));
        }
    }
}

import std.socket : TcpSocket, Socket, SocketSet, SocketException;

/// TCP handler for RPC server
struct TcpHdl {
    TcpSocket tcpsock;  		/// TCP socket
    SocketSet sockset;  		/// socket set
    int _maxconn;       		/// max of TCP connections
	int _maxrecv;       		/// max receive size
	bool close_after_resp;		/// only alow one connection 
}

/// simple standard Thread RPC server
mixin template thrdRPCTcpSrvTemplate(alias C, alias CtorCall) {
    import std.socket : Socket, SocketSet, SocketException;
	import std.experimental.logger : log, LogLevel;
    void thrdRPCTCPSrv(TcpHdl * tcphdl) {
        import core.thread : msecs, Thread;
        import std.conv : to;
        auto _srvimpl = CtorCall;
        auto srvcls = new ImplRpcSrvOfIf!C(_srvimpl);

        Socket[] reads;
        char[] buf = new char[tcphdl._maxrecv];
        string _req, _resp;

		void readAndProcess() {
            foreach (i, r; reads) {
                if (tcphdl.sockset.isSet(r)) {
                    auto _len = r.receive(buf);
                    if (_len == Socket.ERROR) {

                    }
                    else if (_len > 0) {
						log("TCP-RPC server got cmd");
                        try {
                            _req = to!string(buf[0 .. _len]);
                            srvcls.executeMethod(_req, _resp);
                            r.send(_resp);
                        }
                        catch (Exception e) {
                            log(e.msg);
                            return;
                        }
                    }
                    else {
                        try {

                        }
                        catch (SocketException) {
                            log("Socket connection closed.");
                        }
                    }
					if (tcphdl.close_after_resp) {
						r.close();
						import std.algorithm : remove;
						reads = reads.remove(i);
						log("TCP total connection : ", reads.length);
					}
                }
            }
        }

        void connCheck() {
            if (tcphdl.sockset.isSet(tcphdl.tcpsock)) {
                Socket sc = null;
                sc = tcphdl.tcpsock.accept();
                if (reads.length < tcphdl._maxconn) {
                    reads ~= sc;
                }
                else {
                    sc.close();
                }
                scope (failure) {
                    log(LogLevel.critical, "Error accepting");
                    if (sc)
                        sc.close();
                }
            }
        }

        while (true) {
            tcphdl.sockset.add(tcphdl.tcpsock);
            foreach (sock; reads) {
                tcphdl.sockset.add(sock);
            }
            Socket.select(tcphdl.sockset, null, null);
			readAndProcess();
			connCheck();
			if (tcphdl.close_after_resp) {
				tcphdl.sockset.reset();
			}
        }
    }
}
