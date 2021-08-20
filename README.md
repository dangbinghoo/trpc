# trpc Light-weight Thread-Level RPC library for D

## introduction

trpc is a Light-weight RPC library for calling method bettwen threads, RPC call transport
is based on Dlang's thread message-passing, RPC call is just calling interfaces.

trpc takes some code directly from vibe.d (for getting interface meta-infos.), and was inspired by https://code.dlang.org/packages/rpc, and aims to implement simple rpc with minimal dependency.

## Usage

trpc support thread-message-passing, and also support TCP transport for RPC-call. see examples for 
basic usage.
