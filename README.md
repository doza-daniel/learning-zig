# Playing around with zig

## Run the "broker"

```sh
$ zig build run
```

## Run the "generator"

```sh
$ cat ./protocol_json_files/ProduceRequest.json | zig build generate
```
