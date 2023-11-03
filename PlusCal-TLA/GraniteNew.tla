(* Implements 2 rounds (round=0 and round=1) of Granite *)
--------------------------- MODULE GraniteNew ---------------------------

EXTENDS Naturals, TLC, Sequences, FiniteSets

CONSTANT N, PT, Input, Bottom
\* Put number of nodes/participants in N, and in PT, a sequence of their integer powers, e.g., 
\* N=4, PT = <<1,1,1,1>> for equal weights
\* Input is a sequence of input canonical chains, with empty sequence as a base chain, e.g., 
\* Input = << <<"a">>, <<"b">>, <<"a","c">>, <<"a", "c", "d">> >>
\* Bottom = <<"bottom">>

ASSUME N\in Nat /\ Len(PT)=N /\ Len(Input) = N

RECURSIVE SeqSum(_), isPrefix(_,_), Seq2PrefixSet(_), AllPrefixes(_) 

Tickets == 1..N

SeqSum(s) == IF s = <<>> THEN 0 ELSE
   Head(s) + SeqSum(Tail(s))

isPrefix(a,b) == IF Len(a)>Len(b) THEN FALSE ELSE 
                    IF a = <<>> THEN TRUE ELSE 
                        IF Head(a)#Head(b) THEN FALSE ELSE 
                            isPrefix(Tail(a),Tail(b))

Seq2PrefixSet(s) == IF s = <<>> THEN {<<>>} ELSE 
            IF Len(s) = 1 THEN {<<>>,s} ELSE 
            {s} \union Seq2PrefixSet(SubSeq(s, 1, Len(s)-1))

AllPrefixes(input) == IF input = <<>> THEN {} ELSE
            Seq2PrefixSet(Head(input)) \union AllPrefixes(Tail(input))

AllInputPrefixes == AllPrefixes(Input)

TotalQAP == SeqSum(PT)

50percQAP == TotalQAP \div 2 

66percQAP == (2*TotalQAP) \div 3

33percQAP == TotalQAP \div 3

LongestChain(S) == IF S={} THEN <<>> ELSE CHOOSE c \in S: \A d \in S: Len(c)>=Len(d) 

SP == 1..N

(*--algorithm GraniteAlg {
  variables SentMsgs={}; \* Models a broadcast network
  tickets = 1..N; decisions = {}; \*TODO this works only for 1 round of tickets, expand to more
  
  define {
    \* quality related
    SentTypedMsgs(t) == {m \in SentMsgs: (m.type=t)}
    RECURSIVE PrefixPower(_,_)
    PrefixPower(prefix,msgset) == IF msgset={} THEN 0 ELSE
        LET msg == CHOOSE msg \in msgset: TRUE 
            IN IF isPrefix(prefix,msg.proposal) THEN PT[msg.id] + PrefixPower(prefix,msgset\{msg}) ELSE 
             PrefixPower(prefix,msgset\{msg})
    Allowed(M) == IF M = {} THEN {<<>>} ELSE {pref \in AllInputPrefixes: PrefixPower(pref,M) > 50percQAP}
    BestQualityProposal(M) == LongestChain(Allowed(M))
    \* propose related
    SentTypedRoundMsgs(t,r) == {m \in SentMsgs: (m.type=t) /\ (m.round=r)}
    RECURSIVE PowerMsgSet(_)
    PowerMsgSet(msgset) == IF msgset={} THEN 0 ELSE
        LET msg == CHOOSE msg \in msgset: TRUE 
           IN  PT[msg.id] + PowerMsgSet(msgset\{msg})
    Power(t,r)==PowerMsgSet(SentTypedRoundMsgs(t,r)) 
    RECURSIVE ProposalsInMsgSet(_)
    ProposalsInMsgSet(proposeset) == IF proposeset = {} THEN {} ELSE 
        LET msg == CHOOSE msg \in proposeset:TRUE 
        IN {msg.proposal} \union ProposalsInMsgSet(proposeset\{msg})
    RECURSIVE PropWeight(_,_)
    PropWeight(prop,msgset) == IF msgset = {} THEN 0 ELSE 
        LET msg == CHOOSE msg \in msgset: TRUE
        IN  IF msg.proposal = prop THEN PT[msg.id] + PropWeight(prop,msgset\{msg}) ELSE 
        PropWeight(prop,msgset\{msg})
    ModeProposal(proposeset) == CHOOSE prop \in ProposalsInMsgSet(proposeset): 
                                    \A prop2 \in ProposalsInMsgSet(proposeset): 
                                        PropWeight(prop,proposeset)>=PropWeight(prop2,proposeset)
    \* prepare and commit related
    HasStrongQuorum(msgset) == \E v \in ProposalsInMsgSet(msgset): PropWeight(v,msgset) > 66percQAP
    StrongQuorumValue(msgset) == CHOOSE v\in ProposalsInMsgSet(msgset): PropWeight(v,msgset) > 66percQAP  
    
    \* converge related 
    RECURSIVE Mintkt(_) \* minimum ticket in a set
    Mintkt(M) == IF M = {} THEN N+1 ELSE 
    LET msg == CHOOSE msg \in M: TRUE
        IN IF msg.ticket < Mintkt(M\{msg}) THEN msg.ticket ELSE Mintkt(M\{msg})
    LowestTicketProposal(M) == IF M = {} THEN {<<>>} ELSE 
        CHOOSE prop \in ProposalsInMsgSet(M): 
            \E msg \in M: (msg.ticket = Mintkt(M)) /\ (msg.proposal = prop)
  }
  
  \* \* participant calls this to send QUAL msg to peers
   macro sendQUAL() 
   {
     SentMsgs:=SentMsgs \union {[id|-> self, type |->"QUAL", proposal |-> proposal]};
   }
   
   \* participant calls this at the end of its quality/converge step 
   \* (expiration of 2\Delta timer) here we do not wait for StrongQuorum
   \* sends PROPOSE
   macro sendPROP()
   {
     if (round > 0) { \*new version ov Nov 2 does not send PROPOSE in round=0
        proposal := LowestTicketProposal(SentTypedRoundMsgs("CONV",round));  
        SentMsgs:=SentMsgs \union {[id|-> self, type |->"PROP", proposal |-> proposal, round |-> round]};
     }  
   }   
   
   \* sends PREPARE 
   macro sendPREP()
   {
     if (round = 0) {
       proposal := BestQualityProposal(SentTypedMsgs("QUAL"));
       value:=proposal;
     } else {
     await (Power("PROP",round)>66percQAP);
     value:= ModeProposal(SentTypedRoundMsgs("PROP",round)); 
     };
     SentMsgs:=SentMsgs \union {[id|-> self, type |->"PREP", proposal |-> value, round |-> round]};
   }
   
   \* sends COMMIT 
   macro sendCOMM()
   {
     await (Power("PREP",round)>66percQAP);
     if (HasStrongQuorum(SentTypedRoundMsgs("PREP",round)))  
        value:= StrongQuorumValue(SentTypedRoundMsgs("PREP",round)); 
     else {
        value:=Bottom;
     };
     SentMsgs:=SentMsgs \union {[id|-> self, type |->"COMM", proposal |-> value, round |-> round]};
     \*print(SentMsgs);
   }
   
   \*Decide or next round
   macro processCOMMIT()
   {
     await (Power("COMM",round)>66percQAP);
     if (HasStrongQuorum(SentTypedRoundMsgs("COMM",round))) {
        value:= StrongQuorumValue(SentTypedRoundMsgs("COMM",round));
        if (value # Bottom) {
            decisions := decisions \union {value};
            decided := TRUE;
            assert decisions = {value} \* only one element in decisions always (Agreement)
        } else { \* value is Bottom
            if (Cardinality(ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round)))>1) {
                proposal := CHOOSE v \in ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round)): v#Bottom;
                assert (Cardinality(decisions)>0)=>(Cardinality(decisions)=1 /\ \E d\in decisions: d=proposal);
                }
        }
     } 
     else { \*there is no strong quorum - the same as if value is Bottom (TODO: make this less repetitive)
        if (Cardinality(ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round)))>1) {
        proposal := CHOOSE v \in ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round)): v#Bottom;
        assert (Cardinality(decisions)>0)=>(Cardinality(decisions)=1 /\ \E d\in decisions: d=proposal);
        }
     }; 
     round:=round+1;
     \*print(SentMsgs);
   }
   
   \* sends CONVERGE (round>0)
   macro sendCONV() 
   {
        with (t \in tickets) { \* this plays VRF, at least in round=1, assigns random tickets to processes
            tkt :=t;
            tickets := tickets \ {tkt};
        };
        SentMsgs:=SentMsgs \union {[id|-> self, type |->"CONV", proposal |-> proposal, round|-> round, ticket |-> tkt]};
        assert tkt \in Tickets;
   }
   
    
  fair process (name \in SP) 
  variables proposal = Input[self]; round = 0; decided = FALSE; tkt=0; value = Input[self];
 {
 l: while(~decided /\ round < 2) {   \*TODO change round to be param 
     if (round = 0) 
        SendQUAL: sendQUAL();
     else {
        SendCONV: sendCONV();
        SendPROP: sendPROP();
     };
     SendPREP: sendPREP();
     SendCOMM: sendCOMM();
     ProcessCommit: processCOMMIT();
  }
       
  }
}
*)
\* BEGIN TRANSLATION (chksum(pcal) = "b07c14d6" /\ chksum(tla) = "68a6024f")
VARIABLES SentMsgs, tickets, decisions, pc

(* define statement *)
SentTypedMsgs(t) == {m \in SentMsgs: (m.type=t)}
RECURSIVE PrefixPower(_,_)
PrefixPower(prefix,msgset) == IF msgset={} THEN 0 ELSE
    LET msg == CHOOSE msg \in msgset: TRUE
        IN IF isPrefix(prefix,msg.proposal) THEN PT[msg.id] + PrefixPower(prefix,msgset\{msg}) ELSE
         PrefixPower(prefix,msgset\{msg})
Allowed(M) == IF M = {} THEN {<<>>} ELSE {pref \in AllInputPrefixes: PrefixPower(pref,M) > 50percQAP}
BestQualityProposal(M) == LongestChain(Allowed(M))

SentTypedRoundMsgs(t,r) == {m \in SentMsgs: (m.type=t) /\ (m.round=r)}
RECURSIVE PowerMsgSet(_)
PowerMsgSet(msgset) == IF msgset={} THEN 0 ELSE
    LET msg == CHOOSE msg \in msgset: TRUE
       IN  PT[msg.id] + PowerMsgSet(msgset\{msg})
Power(t,r)==PowerMsgSet(SentTypedRoundMsgs(t,r))
RECURSIVE ProposalsInMsgSet(_)
ProposalsInMsgSet(proposeset) == IF proposeset = {} THEN {} ELSE
    LET msg == CHOOSE msg \in proposeset:TRUE
    IN {msg.proposal} \union ProposalsInMsgSet(proposeset\{msg})
RECURSIVE PropWeight(_,_)
PropWeight(prop,msgset) == IF msgset = {} THEN 0 ELSE
    LET msg == CHOOSE msg \in msgset: TRUE
    IN  IF msg.proposal = prop THEN PT[msg.id] + PropWeight(prop,msgset\{msg}) ELSE
    PropWeight(prop,msgset\{msg})
ModeProposal(proposeset) == CHOOSE prop \in ProposalsInMsgSet(proposeset):
                                \A prop2 \in ProposalsInMsgSet(proposeset):
                                    PropWeight(prop,proposeset)>=PropWeight(prop2,proposeset)

HasStrongQuorum(msgset) == \E v \in ProposalsInMsgSet(msgset): PropWeight(v,msgset) > 66percQAP
StrongQuorumValue(msgset) == CHOOSE v\in ProposalsInMsgSet(msgset): PropWeight(v,msgset) > 66percQAP


RECURSIVE Mintkt(_)
Mintkt(M) == IF M = {} THEN N+1 ELSE
LET msg == CHOOSE msg \in M: TRUE
    IN IF msg.ticket < Mintkt(M\{msg}) THEN msg.ticket ELSE Mintkt(M\{msg})
LowestTicketProposal(M) == IF M = {} THEN {<<>>} ELSE
    CHOOSE prop \in ProposalsInMsgSet(M):
        \E msg \in M: (msg.ticket = Mintkt(M)) /\ (msg.proposal = prop)

VARIABLES proposal, round, decided, tkt, value

vars == << SentMsgs, tickets, decisions, pc, proposal, round, decided, tkt, 
           value >>

ProcSet == (SP)

Init == (* Global variables *)
        /\ SentMsgs = {}
        /\ tickets = 1..N
        /\ decisions = {}
        (* Process name *)
        /\ proposal = [self \in SP |-> Input[self]]
        /\ round = [self \in SP |-> 0]
        /\ decided = [self \in SP |-> FALSE]
        /\ tkt = [self \in SP |-> 0]
        /\ value = [self \in SP |-> Input[self]]
        /\ pc = [self \in ProcSet |-> "l"]

l(self) == /\ pc[self] = "l"
           /\ IF ~decided[self] /\ round[self] < 2
                 THEN /\ IF round[self] = 0
                            THEN /\ pc' = [pc EXCEPT ![self] = "SendQUAL"]
                            ELSE /\ pc' = [pc EXCEPT ![self] = "SendCONV"]
                 ELSE /\ pc' = [pc EXCEPT ![self] = "Done"]
           /\ UNCHANGED << SentMsgs, tickets, decisions, proposal, round, 
                           decided, tkt, value >>

SendPREP(self) == /\ pc[self] = "SendPREP"
                  /\ IF round[self] = 0
                        THEN /\ proposal' = [proposal EXCEPT ![self] = BestQualityProposal(SentTypedMsgs("QUAL"))]
                             /\ value' = [value EXCEPT ![self] = proposal'[self]]
                        ELSE /\ (Power("PROP",round[self])>66percQAP)
                             /\ value' = [value EXCEPT ![self] = ModeProposal(SentTypedRoundMsgs("PROP",round[self]))]
                             /\ UNCHANGED proposal
                  /\ SentMsgs' = (SentMsgs \union {[id|-> self, type |->"PREP", proposal |-> value'[self], round |-> round[self]]})
                  /\ pc' = [pc EXCEPT ![self] = "SendCOMM"]
                  /\ UNCHANGED << tickets, decisions, round, decided, tkt >>

SendCOMM(self) == /\ pc[self] = "SendCOMM"
                  /\ (Power("PREP",round[self])>66percQAP)
                  /\ IF HasStrongQuorum(SentTypedRoundMsgs("PREP",round[self]))
                        THEN /\ value' = [value EXCEPT ![self] = StrongQuorumValue(SentTypedRoundMsgs("PREP",round[self]))]
                        ELSE /\ value' = [value EXCEPT ![self] = Bottom]
                  /\ SentMsgs' = (SentMsgs \union {[id|-> self, type |->"COMM", proposal |-> value'[self], round |-> round[self]]})
                  /\ pc' = [pc EXCEPT ![self] = "ProcessCommit"]
                  /\ UNCHANGED << tickets, decisions, proposal, round, decided, 
                                  tkt >>

ProcessCommit(self) == /\ pc[self] = "ProcessCommit"
                       /\ (Power("COMM",round[self])>66percQAP)
                       /\ IF HasStrongQuorum(SentTypedRoundMsgs("COMM",round[self]))
                             THEN /\ value' = [value EXCEPT ![self] = StrongQuorumValue(SentTypedRoundMsgs("COMM",round[self]))]
                                  /\ IF value'[self] # Bottom
                                        THEN /\ decisions' = (decisions \union {value'[self]})
                                             /\ decided' = [decided EXCEPT ![self] = TRUE]
                                             /\ Assert(decisions' = {value'[self]}, 
                                                       "Failure of assertion at line 147, column 13 of macro called at line 189, column 21.")
                                             /\ UNCHANGED proposal
                                        ELSE /\ IF Cardinality(ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round[self])))>1
                                                   THEN /\ proposal' = [proposal EXCEPT ![self] = CHOOSE v \in ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round[self])): v#Bottom]
                                                        /\ Assert((Cardinality(decisions)>0)=>(Cardinality(decisions)=1 /\ \E d\in decisions: d=proposal'[self]), 
                                                                  "Failure of assertion at line 151, column 17 of macro called at line 189, column 21.")
                                                   ELSE /\ TRUE
                                                        /\ UNCHANGED proposal
                                             /\ UNCHANGED << decisions, 
                                                             decided >>
                             ELSE /\ IF Cardinality(ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round[self])))>1
                                        THEN /\ proposal' = [proposal EXCEPT ![self] = CHOOSE v \in ProposalsInMsgSet(SentTypedRoundMsgs("COMM",round[self])): v#Bottom]
                                             /\ Assert((Cardinality(decisions)>0)=>(Cardinality(decisions)=1 /\ \E d\in decisions: d=proposal'[self]), 
                                                       "Failure of assertion at line 158, column 9 of macro called at line 189, column 21.")
                                        ELSE /\ TRUE
                                             /\ UNCHANGED proposal
                                  /\ UNCHANGED << decisions, decided, value >>
                       /\ round' = [round EXCEPT ![self] = round[self]+1]
                       /\ pc' = [pc EXCEPT ![self] = "l"]
                       /\ UNCHANGED << SentMsgs, tickets, tkt >>

SendQUAL(self) == /\ pc[self] = "SendQUAL"
                  /\ SentMsgs' = (SentMsgs \union {[id|-> self, type |->"QUAL", proposal |-> proposal[self]]})
                  /\ pc' = [pc EXCEPT ![self] = "SendPREP"]
                  /\ UNCHANGED << tickets, decisions, proposal, round, decided, 
                                  tkt, value >>

SendCONV(self) == /\ pc[self] = "SendCONV"
                  /\ \E t \in tickets:
                       /\ tkt' = [tkt EXCEPT ![self] = t]
                       /\ tickets' = tickets \ {tkt'[self]}
                  /\ SentMsgs' = (SentMsgs \union {[id|-> self, type |->"CONV", proposal |-> proposal[self], round|-> round[self], ticket |-> tkt'[self]]})
                  /\ Assert(tkt'[self] \in Tickets, 
                            "Failure of assertion at line 173, column 9 of macro called at line 184, column 19.")
                  /\ pc' = [pc EXCEPT ![self] = "SendPROP"]
                  /\ UNCHANGED << decisions, proposal, round, decided, value >>

SendPROP(self) == /\ pc[self] = "SendPROP"
                  /\ IF round[self] > 0
                        THEN /\ proposal' = [proposal EXCEPT ![self] = LowestTicketProposal(SentTypedRoundMsgs("CONV",round[self]))]
                             /\ SentMsgs' = (SentMsgs \union {[id|-> self, type |->"PROP", proposal |-> proposal'[self], round |-> round[self]]})
                        ELSE /\ TRUE
                             /\ UNCHANGED << SentMsgs, proposal >>
                  /\ pc' = [pc EXCEPT ![self] = "SendPREP"]
                  /\ UNCHANGED << tickets, decisions, round, decided, tkt, 
                                  value >>

name(self) == l(self) \/ SendPREP(self) \/ SendCOMM(self)
                 \/ ProcessCommit(self) \/ SendQUAL(self) \/ SendCONV(self)
                 \/ SendPROP(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == (\E self \in SP: name(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in SP : WF_vars(name(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 
=============================================================================
\* Modification History
\* Last modified Thu Nov 02 21:21:48 CET 2023 by marko
\* Created Thu Nov 02 17:53:45 CET 2023 by marko