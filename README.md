# devefi_icrc_reader

## Install
```
mops add devefi-icrc-reader
```

## Usage
```motoko
import IcrcReader "mo:devefi-icrc-reader";


stable let icrc_reader_mem = IcrcReader.Mem();
let icrc_reader = IcrcReader.Reader({
    mem = icrc_reader_mem;
    ledger_id = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
    start_from_block = #last;
    onError = func (e: Text) {}; // In case a cycle throws an error
    onCycleEnd = func (instructions: Nat64) {}; // returns the instructions the cycle used. 
                                                // It can include multiple calls to onRead
    onRead = func (transactions: [IcrcReader.Transaction]) {
        // do something here
    };
})

icrc_reader.start();


```
