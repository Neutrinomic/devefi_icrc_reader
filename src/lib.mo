import Ledger "./icrc_ledger";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Timer "mo:base/Timer";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Vector "mo:vector";
import Prim "mo:⛔";

module {

    public type Mem = {
            var last_indexed_tx : Nat;
            var started: Bool;
        };

    type TransactionUnordered = {
            start : Nat;
            transactions : [Ledger.Transaction];
        };
        
    public func Mem() : Mem {
            return {
                var last_indexed_tx = 0;
                var started = false;
            };
        };

    public class Reader({
        mem : Mem;
        ledger_id : Principal;
        start_from_block: {#id:Nat; #last};
        onError : (Text) -> (); // If error occurs during following and processing it will return the error
        onCycle : (Nat64) -> (); // Measure performance of following and processing transactions. Returns instruction count
        onRead : [Ledger.Transaction] -> ();
    }) {

        let ledger = actor (Principal.toText(ledger_id)) : Ledger.Self;

        private func cycle() : async () {
            if (not mem.started) return;
            let inst_start = Prim.performanceCounter(1); // 1 is preserving with async

            if (mem.last_indexed_tx == 0) {
                switch(start_from_block) {
                    case (#id(id)) {
                        mem.last_indexed_tx := id;
                    };
                    case (#last) {
                        let rez = await ledger.get_transactions({
                            start = 0;
                            length = 0;
                        });
                        mem.last_indexed_tx := rez.log_length -1;
                    };
                };
            };

            let rez = await ledger.get_transactions({
                start = mem.last_indexed_tx;
                length = 1000;
            });

            if (rez.archived_transactions.size() == 0) {
                // We can just process the transactions
                onRead(rez.transactions);
                mem.last_indexed_tx += rez.transactions.size();
            } else {
                // We need to collect transactions from archive and get them in order
                let unordered = Vector.new<TransactionUnordered>(); // Probably a better idea would be to use a large enough var array

                for (atx in rez.archived_transactions.vals()) {
                    let txresp = await atx.callback({
                        start = atx.start;
                        length = atx.length;
                    });

                    Vector.add(
                        unordered,
                        {
                            start = atx.start;
                            transactions = txresp.transactions;
                        },
                    );
                };

                let sorted = Array.sort<TransactionUnordered>(Vector.toArray(unordered), func(a, b) = Nat.compare(a.start, b.start));

                for (u in sorted.vals()) {
                    assert (u.start == mem.last_indexed_tx);
                    onRead(u.transactions);
                    mem.last_indexed_tx += u.transactions.size();
                };

                if (rez.transactions.size() != 0) {
                    onRead(rez.transactions);
                    mem.last_indexed_tx += rez.transactions.size();
                };
            };

            let inst_end = Prim.performanceCounter(1); // 1 is preserving with async
            onCycle(inst_end - inst_start);
        };

        private func cycle_shell() : async () {
            try {
                // We need it async or it won't throw errors
                await cycle();
            } catch (e) {
                onError("cycle:" # Principal.toText(ledger_id) # ":" # Error.message(e));
            };

            if (mem.started) ignore Timer.setTimer(#seconds 2, cycle_shell);
        };

        public func start() {
            mem.started := true;
            ignore Timer.setTimer(#seconds 2, cycle_shell);
        };

        public func stop() {
            mem.started := false;
        }
    };

};
