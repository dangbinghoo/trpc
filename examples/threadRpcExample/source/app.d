import std.stdio;

import trpc.client;

import std.experimental.logger;

/// TODO: now need to public import all interface and related symbols.
public import rpcif;

class rpcServer : rpcMethod {
	private string _msg;

	///
	this(string msg) {
		_msg = msg;
	}

	RetInfo hello_rpc(string a, out string b, out int c, paramA pa, out paramB pb)
	{
		RetInfo ret;
		writeln("a = ", a);
		b = "hello_b";
		c = 3;
		writeln("pa is ", pa);
		pb.bb1 = 5;
		pb.bb2 = "hello_rmt_bb2";
		ret.info = "called from remote!";
		ret.status = 0;
		return ret;
	}

	int hello_a (int a, int b) {
		writeln("_msg is : ", _msg);
		return a + b;
	}

    double add_b(double a, double b) {
        return a + b;
    }

	void print() {
		writeln("MSG is : ", _msg);
	}
}

import trpc.server;

import std.concurrency : spawn, Tid;
import core.thread : msecs, Thread;

mixin thrdRPCSrvThreadTemplate!(rpcServer, new rpcServer("eee")) trpcSrv;

private void trpcSrvThread2() {
	auto _srvimpl = new rpcServer("bbb");
	auto srvcls = new ImplRpcSrvOfIf!(rpcServer)(_srvimpl);

	while (true) {
		thrdRPCSrvProcessNoneBlock!(rpcServer)(srvcls, 200);
		Thread.sleep(msecs(100));
	}
}

void threadRPCExample() {
	Tid srvId = spawn(&trpcSrv.thrdRPCSrvThread);
	//Tid srvId = spawn(&trpcSrvThread2);
    writeln("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    auto mycli = new ThrdRPClient!(rpcMethod, 200)(srvId);
	string b = "XXXX"; int c = 5; paramA pa; paramB pb;
	pa.aa1 = 10; pa.aa2 = "lalala";
    mycli.hello_rpc("a", b, c, pa, pb).writeln;
	writeln(`---------------------------------------------`);
    mycli.hello_a(1, 2).writeln;
	writeln("now b = ", b, ", c = ", c);
    writeln("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

	import core.thread : Thread, msecs;
	while (true) {
		Thread.sleep(msecs(1000));
	}
}


void main()
{
	threadRPCExample();
}
