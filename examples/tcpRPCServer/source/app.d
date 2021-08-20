import std.stdio;
import std.experimental.logger : log;

public import rpcif;
import trpc.server;
import std.socket;

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

mixin thrdRPCTcpSrvTemplate!(rpcServer, new rpcServer("tcp")) tcpRpcSrv;

void runTCPServer() {
	TcpHdl srvhdl;
	// init tcp server
	srvhdl.tcpsock = new TcpSocket();
	srvhdl.tcpsock.blocking = false; 
	srvhdl._maxconn = 2;
	srvhdl._maxrecv = 4096;
	srvhdl.sockset = new SocketSet(srvhdl._maxconn + 1);
	log("init tcp server done!");
	try {
		srvhdl.tcpsock.bind(new InternetAddress("127.0.0.1", 6100));
		srvhdl.tcpsock.listen(srvhdl._maxconn);
	}
	catch (Exception e) {
		log(e.msg);
	}
	log("running TCP-RPC server...");
	tcpRpcSrv.thrdRPCTCPSrv(&srvhdl);
}

void main()
{
	runTCPServer();
	// // server can run in a background thread.
	// import std.concurrency : spawn;
	// spawn(&runTCPServer);
}
