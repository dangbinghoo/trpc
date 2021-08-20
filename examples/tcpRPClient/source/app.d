import std.stdio;

import trpc.client;

public import rpcif;

import std.socket;

void main()
{
	import core.thread : Thread, msecs;
	Thread.sleep(msecs(3000));

	// tcp client
	TcpSocket clisock = new TcpSocket();
	clisock.blocking = true;
	clisock.connect(new InternetAddress("127.0.0.1", 6100));

	writeln("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    auto mycli = new ThrdRPCTcpClient!(rpcMethod, 200)(clisock, 4096);
	string b = "foo"; int c = 5; paramA pa; paramB pb;
	pa.aa1 = 10; pa.aa2 = "lalala";

	while(true) {
		writeln("===================================================");
		mycli.hello_rpc("a", b, c, pa, pb).writeln;
		writeln(`---------------------------------------------`);
		mycli.hello_a(1, 2).writeln;
		writeln("now b = ", b, ", c = ", c);
		writeln("===================================================");

		//Thread.sleep(msecs(2000));
	}
}
