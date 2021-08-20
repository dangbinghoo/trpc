/**
 * tools to get Interface meta info for auto-generate implementation.
 * 
 *   Copied from https://github.com/boolangery/d-autointf
 *   Modified to remove extra vibe.d dependency for better footprint size.
 *   
 *   Copyright: © 2018 Eliott Dumeix
 *   License: Subject to the terms of the MIT license
 *
 */
module ifinfo;


import std.traits : hasUDA, moduleName;

/**
 * No-Auto-Implement attribute
 */
package struct NoAutoImplMethod {
}

/**
 * noImpl attribute
 */
NoAutoImplMethod noImpl() @safe
{
    return NoAutoImplMethod();
}

/*  attributes utils */
private enum isEnabledMethod(alias M) = !hasUDA!(M, NoAutoImplMethod);

/// Method Param
struct MethodParam {
    string name;      /// param name
    string type;      /// param type
    string storetype; /// param storage-type : in or out
}

/// Method info
struct MethodInfo {
    string        name;     /// method name
    MethodParam[] params;   /// method params
    string        rettype;  /// method return type
    string[] _customtypes;  /// method related user defined types
}

/// Get Interfaces Info for a class or pure interface.
struct IfInfo(T) if (is(T == class) || is(T == interface))
{
    import std.traits : InterfacesTuple, Parameters, ReturnType,
                        ParameterStorageClassTuple, ParameterStorageClass, ParameterIdentifierTuple, isBuiltinType;
    import std.typetuple : TypeTuple;

	alias _interfaces =  InterfacesTuple!(T);

    static if (is(T == interface))
        alias I = T;
    else
        alias I = _interfaces[0];

    /// members
    static immutable membernames = [__traits(allMembers, I)];

    //pragma(msg, "member is ", membernames);

    /// Aliases to all interface methods (Compile-time).
    alias Members = GetMembers!(); 

    /** Aliases for each method (Compile-time).
    This tuple has the same number of entries as `methods`. */
    alias Methods = GetMethods!();

    /// Number of methods
    enum mthcnt = membernames.length;

    /// the method Infos of an Interface or Class
    MethodInfo[mthcnt] methodInfos;

    /// Fills the struct with information.
    this(int dummy) {
        getInfos();
    }

    // copying this struct is costly, so we forbid it
    @disable this(this);

	/// Get all interface method infos.
    MethodInfo[] getInfos() {
        foreach (i, f; Methods) {      
            methodInfos[i].name = membernames[i];
            alias _paramtypes = Parameters!f;
            alias _paramident = ParameterIdentifierTuple!f;
            alias _paramstoretype = ParameterStorageClassTuple!f;
            //pragma(msg, "ptype: ", _paramtypes);
            //pragma(msg, "paramstoretype: ", _paramstoretype);
            foreach (pi, p; _paramtypes) {
                MethodParam pr;
                pr.type = p.stringof;
                if (! isBuiltinType!p) {
                    methodInfos[i]._customtypes ~= p.stringof;
                }
                pr.name = _paramident[pi];
                if (_paramstoretype[pi] == ParameterStorageClass.out_)
                    pr.storetype = "out";
                else if (_paramstoretype[pi] == ParameterStorageClass.in_)
                    pr.storetype = "in";
                else if (_paramstoretype[pi] == ParameterStorageClass.ref_)
                    pr.storetype = "ref";
                else if (_paramstoretype[pi] == ParameterStorageClass.return_)
                    pr.storetype = "return";
                else if (_paramstoretype[pi] == ParameterStorageClass.none)
                    pr.storetype = "none";
                methodInfos[i].params ~= pr;
            }
            methodInfos[i].rettype = ReturnType!f.stringof;
            if (! isBuiltinType!(ReturnType!f)) {
                methodInfos[i]._customtypes ~= methodInfos[i].rettype;
            }
        }

        return methodInfos;
    }

    private template SubInterfaceType(alias F) {
        import std.traits : ReturnType, isInstanceOf;

        alias RT = ReturnType!F;
        static if (is(RT == interface))
            alias SubInterfaceType = RT;
        else
            alias SubInterfaceType = void;
    }

    private template GetMembers() {
        import std.traits : MemberFunctionsTuple;
        template Impl(size_t idx) {
            static if (idx < membernames.length) {
                enum name = membernames[idx];
                static if (name.length != 0)
                    alias Impl = TypeTuple!(MemberFunctionsTuple!(I, name), Impl!(idx + 1));
                else
                    alias Impl = Impl!(idx + 1);
            }
            else
                alias Impl = TypeTuple!();
        }

        alias GetMembers = Impl!0;
    }

    private template GetMethods() {
        template Impl(size_t idx) {
            static if (idx < Members.length) {
                alias F = Members[idx];
                alias SI = SubInterfaceType!F;
                static if (is(SI == void) && isEnabledMethod!F)
                    alias Impl = TypeTuple!(F, Impl!(idx + 1));
                else
                    alias Impl = Impl!(idx + 1);
            }
            else
                alias Impl = TypeTuple!();
        }

        alias GetMethods = Impl!0;
    }
}
