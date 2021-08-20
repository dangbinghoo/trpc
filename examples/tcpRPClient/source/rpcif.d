module rpcif;

struct RetInfo {
	int status;
	string info;
}

struct paramA {
	int aa1;
	string aa2;
}

struct paramB {
	int bb1;
	string bb2; 
}

interface rpcMethod {
	RetInfo hello_rpc(string a, out string b, out int c, paramA pa, out paramB pb);
	int hello_a (int a, int b);
}
