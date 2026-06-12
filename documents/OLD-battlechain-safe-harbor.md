> **DEPRECATED — DO NOT RELY ON THIS DOCUMENT.** It is superseded by [`seal-agreement-modified.md`](seal-agreement-modified.md), and its terms (including default exploit coverage, governing law, and dispute resolution) no longer apply. It is retained for historical reference only.

# BATTLECHAIN SAFE HARBOR AGREEMENT

## & RELATED MATERIALS

**v1.0**

---

This **BATTLECHAIN SAFE HARBOR AGREEMENT (this "Agreement")** sets forth the terms and conditions of the Program and is being entered into by, and is binding upon, each Protocol Community that adopts the Agreement by calling the `requestUnderAttack` function on the BattleChain AttackRegistry OR by having this Agreement apply to their Protocol by default, and each Whitehat who conducts or attempts an Eligible Exploit during a Covered Period (collectively referred to as "**Parties**"). Certain capitalized terms used in this Agreement are defined in Exhibit A.

A "**Covered Period**" means either: (i) a **Declared Attack Period** when a Protocol has voluntarily opted into attack mode via the AttackRegistry; or (ii) an **Urgent Blackhat Exploit** when a Protocol is under active malicious attack and a Whitehat intervenes to rescue funds.

---

## Background Information

a. This Agreement has been prepared for BattleChain, a production Layer 2 blockchain built on the ZKsync stack. BattleChain is designed to provide enhanced security for protocols by giving Whitehats more freedom and incentive to identify vulnerabilities. BattleChain provides an environment where Protocol Communities can voluntarily declare their contracts to be "under attack" to invite ethical hackers to test their security before or alongside deployments on other networks.

b. This Agreement provides coverage for Whitehats in **two distinct scenarios**:
   - **Declared Attack Period**: When a Protocol Community voluntarily opts into attack mode by calling `requestUnderAttack` on the AttackRegistry, inviting Whitehats to test their security; AND
   - **Urgent Blackhat Exploit**: When a Protocol is under active attack by a malicious actor, and a Whitehat intervenes to rescue funds before they can be stolen.

c. Each Protocol Community adopting this Agreement for its corresponding Protocol seeks to encourage Whitehats to responsibly test, seek to penetrate, and otherwise stress-test the Protocol during a Declared Attack Period, AND to rescue funds during an Urgent Blackhat Exploit, and, pursuant to the Program, potentially receive a Reward for conducting Eligible Exploits. Only Whitehats who agree to the terms and conditions of this Agreement and conduct an Eligible Exploit pursuant to and in accordance with the terms and conditions of this Agreement will be eligible to participate in the Program and potentially receive a Reward.

d. Each Whitehat adopting this Agreement seeks to test and exploit a Protocol with respect to which this Agreement has been adopted by the Protocol Community, for the purpose of completing an Eligible Exploit within the bounds set out in this Agreement, and accordingly wishes to enter into this Agreement to participate in the Program and become eligible to potentially receive a Reward pursuant to the parameters set forth herein.

e. **Critical Limitation**: Vulnerabilities discovered on BattleChain may exist in identical or similar code deployed on Ethereum mainnet or other blockchains. This Agreement provides protections ONLY for exploits conducted on BattleChain during a Covered Period (either a Declared Attack Period or an Urgent Blackhat Exploit). Whitehats must not disclose or exploit vulnerabilities on other chains without following responsible disclosure procedures for those deployments.

---

## Agreement

### 1. Eligible Protocols

#### 1.1 Adoption of this Agreement by Protocol Communities

a. A Protocol is eligible for Stress Test Exploits under this Agreement if this Agreement has been duly adopted by the Protocol Community associated with such Protocol in accordance with the Adoption Procedures, and such adoption has not been subsequently renounced, revoked, annulled, voided, or rescinded by the Protocol Community.

b. This Agreement shall be:
   - i. binding upon and enforceable against any Protocol Community by the Protocol Community adopting this Agreement in accordance with the DAO Adoption Procedures;
   - ii. after adoption of this Agreement by the DAO Adoption Procedures, binding upon and enforceable against any Security Team with respect to any Protocol, by the Security Team adopting this Agreement in accordance with the Security Team Adoption Procedures; and
   - iii. after adoption of this Agreement by the DAO Adoption Procedures, binding upon and enforceable against any Users with respect to any Protocol, by the Users adopting this Agreement in accordance with the User Adoption Procedures.

c. "**DAO Adoption Procedures**" means that this Agreement has been duly adopted and approved by or on behalf of a Protocol Community by such Protocol Community, by DAO Approval, or a person, group, entity, or other smart contract expressly and specifically authorized by DAO Approval to act for or on behalf of such Protocol Community in such respect, having properly executed a call of the `requestUnderAttack` function of the BattleChain AttackRegistry smart contract, followed by approval via the `approveAttack` function by the Registry Moderator.

d. The `requestUnderAttack` function call shall include or reference the following parameters (to be stored on-chain or via URI reference):
   - i. the **protocolName**, being a string specifying the name of the Protocol for which this Agreement is being adopted;
   - ii. the **contractAddresses**, being the addresses of smart contracts included in the scope of Eligible Stress Test Exploits;
   - iii. the **assetRecoveryAddress**, being the blockchain address to which Whitehats shall deposit Returnable Assets;
   - iv. the **contactDetails**, specifying contact information for the Protocol Community for receiving notifications pursuant to this Agreement;
   - v. the **bountyTerms**, being a struct specifying:
      - A. the Bounty Percentage (recommended: 10%);
      - B. the Bounty Cap in USD (recommended: $5,000,000);
      - C. whether the Bounty can be retained by the Whitehat from Exploited Assets;
      - D. identity requirements for Bounty payment (Anonymous, Pseudonymous, or Named);
   - vi. the **agreementURI**, being a URI pointing to the exact text of this Agreement as of the date of adoption. The URI may use any IANA-registered URI scheme (including but not limited to IPFS, HTTPS, data URIs with base64 encoding per RFC 4648, CAIP-322, or EIP-831 formats).

e. In the event that a Protocol does not have a DAO, the Attack Moderator (as set in the AttackRegistry) may utilize the DAO Adoption Procedures to indicate adoption of this Agreement with respect to the Protocol.

#### 1.2 Contract States and Covered Periods

a. The BattleChain AttackRegistry tracks contracts through the following states:
   - **NOT_DEPLOYED**: Contract has not been registered
   - **NEW_DEPLOYMENT**: Contract is newly deployed (window to request attack mode as defined by `PROMOTION_WINDOW` in the AttackRegistry)
   - **ATTACK_REQUESTED**: Protocol has requested to enter attack mode, pending approval
   - **UNDER_ATTACK**: Contract is in Declared Attack Period - Stress Test Exploits are authorized
   - **PROMOTION_REQUESTED**: Contract is still in Declared Attack Period during promotion delay (as defined by `PROMOTION_DELAY` in the AttackRegistry) - Stress Test Exploits remain authorized
   - **PRODUCTION**: Terminal state - contract is protected, only Rescue Exploits during Urgent Blackhat Exploits are authorized

b. "**Covered Period**" means the period during which Whitehats are authorized to conduct Eligible Exploits under this Agreement. There are two types of Covered Periods:

   - i. **Declared Attack Period**: The period during which `isUnderAttack` returns `true` for a Protocol's contracts on the AttackRegistry (i.e., when contracts are in `UNDER_ATTACK` or `PROMOTION_REQUESTED` state). During a Declared Attack Period, Whitehats are authorized to conduct Stress Test Exploits. The Declared Attack Period continues through the promotion delay to ensure Whitehats have adequate time to test before production status.

   - ii. **Urgent Blackhat Exploit**: An ongoing or imminent Exploit of a Protocol by a Blackhat that, absent intervention, is reasonably likely to result in material loss to the Protocol or its Users. During an Urgent Blackhat Exploit, Whitehats are authorized to conduct Rescue Exploits to secure Assets before they can be stolen by the Blackhat.

c. **Urgent Blackhat Exploit Coverage**: This Agreement provides protection for Whitehats who conduct Rescue Exploits during an Urgent Blackhat Exploit, regardless of the Protocol's state in the AttackRegistry, including when the Protocol is in `PRODUCTION` state, **provided that**:
   - i. An actual Urgent Blackhat Exploit was occurring or imminent at the time of the Whitehat's intervention;
   - ii. The Whitehat acted in good faith to rescue funds that would otherwise have been stolen;
   - iii. The Whitehat returns all Returnable Assets to the Asset Recovery Address (or a reasonable alternative if no Asset Recovery Address was designated);
   - iv. The Whitehat complies with all other terms of this Agreement.

d. **Default Adoption for Urgent Blackhat Exploits**: All Protocols deployed on BattleChain are deemed to have adopted this Agreement for purposes of Urgent Blackhat Exploit coverage ONLY, unless the Protocol Community has explicitly opted out by on-chain declaration. This default adoption does NOT apply to Declared Attack Period coverage, which requires explicit opt-in via `requestUnderAttack`.

e. **Automatic Transition**: If a Protocol in `NEW_DEPLOYMENT` state does not request attack mode within the `PROMOTION_WINDOW` (as defined in the AttackRegistry), the contract automatically transitions to `PRODUCTION` state and is NOT covered by Declared Attack Period provisions of this Agreement. However, Urgent Blackhat Exploit coverage continues to apply.

f. **Promotion to Production**: When a Protocol calls `promote` from `UNDER_ATTACK` state, there is a delay (as defined by `PROMOTION_DELAY` in the AttackRegistry) before the contract transitions to `PRODUCTION`. During this delay, the contract is in `PROMOTION_REQUESTED` state and remains in the Declared Attack Period. The Registry Moderator may also call `instantPromote` to immediately transition a contract to `PRODUCTION`. Once in `PRODUCTION` state, only Rescue Exploits during Urgent Blackhat Exploits are authorized; unauthorized exploits may constitute criminal activity.

#### 1.3 Certain Defined Terms

For purposes of this Agreement, the following capitalized terms have the meanings ascribed to them below:

a. "**Adoption Procedures**" means:
   - i. the DAO Adoption Procedures;
   - ii. the Security Team Adoption Procedures; and
   - iii. the User Adoption Procedures.

b. "**DAO**" means any Entity or group or set of persons, whether or not incorporated, associated, or affiliated, that in-whole or in-part govern a blockchain-based protocol or any funding, personnel, or resources dedicated primarily for maintenance, development, marketing, operation, or improvement of any blockchain-based protocol.

c. "**DAO Approval**" means, with respect to a given Protocol Community and a given matter or action, that such matter or action has been validly approved in accordance with the specific governance process of the Protocol.

d. "**Security Team**" means, with respect to a given Protocol, any Entity, person, or group of persons (other than a DAO) having any privileges or powers with respect to the upgrading, parameterization, freezing, or upgrading of a Protocol or recovery of funds from an Exploit of a Protocol.

e. "**Attack Moderator**" means the address designated in the AttackRegistry's `s_contractInfo` mapping for a specific contract, having authority to call `requestUnderAttack`, `promote`, and `transferAttackModerator` for that contract.

f. "**Registry Moderator**" means the address set by the AttackRegistry owner that can call `approveAttack` and `instantPromote`.

g. "**Users**" of a Protocol means all persons who have Tokens on deposit with, held by, or otherwise subject to the full or partial direct or indirect custody, control, or influence of the Protocol.

h. "**Protocol**" means the smart contracts set during the DAO Adoption Procedures, such contracts being the on-chain systems for which the Protocol Community has adopted the Program.

i. "**Protocol Community**" means, with respect to a given blockchain-based protocol at a given time, all of the Protocol Community Members as of such time.

j. "**Protocol Community Member**" means, with respect to a given blockchain-based protocol at a given time, each of:
   - i. the DAO governing such protocol;
   - ii. each User of such protocol; and
   - iii. the Security Team for such protocol and each member of such Security Team.

k. "**Token**" means all tokens, cryptocurrencies, virtual assets, digital assets, and other units of account or mediums of exchange that are transferable on a blockchain system.

---

### 2. Covered Exploits & Rewards

#### 2.1 Eligible Whitehats to be Compensated for Eligible Exploits

If an Eligible Whitehat performs an Eligible Exploit pursuant to and in accordance with this Agreement, then, as the sole compensation and reward for such performance, the Eligible Whitehat may be entitled to: (i) payment or retention of the applicable Bounty as set forth in Section 3; and (ii) the grant of a release of Claims as set forth in Section 6.2 (the consideration described in the preceding clauses '(i)' and '(ii)', collectively, the "**Reward**").

An "**Eligible Exploit**" means either an Eligible Stress Test Exploit or an Eligible Rescue Exploit, as defined in Section 2.3.

#### 2.2 Limited Scope - BattleChain Only

**CRITICAL**: This Agreement and the Reward granted hereunder are intended solely to provide compensation to Eligible Whitehats who complete Eligible Exploits of Tokens on the BattleChain network during a Covered Period.

a. **BattleChain Only**: This Agreement provides NO authorization, protection, or immunity for exploits conducted on any blockchain other than BattleChain, including but not limited to Ethereum mainnet or any other Layer 2 network.

b. **Covered Period Only**: Even on BattleChain, this Agreement provides authorization, protection, or immunity ONLY for:
   - i. **Stress Test Exploits** conducted during a **Declared Attack Period** (contracts in `UNDER_ATTACK` state); OR
   - ii. **Rescue Exploits** conducted during an **Urgent Blackhat Exploit** (active malicious attack in progress).

c. **Mainnet Disclosure Prohibition**: If a Whitehat discovers a vulnerability while conducting an Exploit on BattleChain, and that vulnerability may affect identical or similar code deployed on other networks:
   - i. The Whitehat **SHALL NOT** exploit such vulnerability on any other network;
   - ii. The Whitehat **SHALL NOT** disclose such vulnerability to any third party who might exploit it on other networks;
   - iii. The Whitehat **SHALL** follow responsible disclosure procedures by notifying the Protocol Community via the contact details provided during adoption (or, if not available, via any reasonable means);
   - iv. The Whitehat **MAY** be eligible for additional bounties from the Protocol Community for responsible disclosure of cross-chain vulnerabilities, at the Protocol Community's discretion.

d. **Violation Consequences**: Any Whitehat who exploits or discloses vulnerabilities affecting other networks in violation of Section 2.2(c):
   - i. Shall forfeit any Reward under this Agreement;
   - ii. Shall not be protected by the releases in Section 6;
   - iii. May be subject to legal action by the Protocol Community and/or affected third parties;
   - iv. May be subject to criminal prosecution for unauthorized computer access.

#### 2.3 Certain Defined Terms

a. **Exploit**. An "**Exploit**" means an attack, hack, or exploit against all or any part of a Protocol.

b. **Blackhat**. A "**Blackhat**" means any Person who conducts or attempts to conduct an Exploit with the intent to steal, misappropriate, or permanently deprive the Protocol or its Users of Assets, or who otherwise acts maliciously with respect to a Protocol.

c. **Whitehat**. A "**Whitehat**" means any Person who conducts or attempts to conduct an Exploit with the intent to secure Assets for the benefit of the Protocol or its Users, rather than to steal or misappropriate such Assets.

d. **Eligible Whitehat**. A Person is an "**Eligible Whitehat**" with respect to a particular Exploit if and only if such person:
   - i. has read, understood, and agreed to be bound by this Agreement with respect to such Exploit;
   - ii. the representations and warranties in Section 5 are accurate and complete as to such person in connection with and at all times relevant to such Exploit;
   - iii. such person has not breached, contravened, or violated any provision of this Agreement or any applicable or otherwise relevant law, legal order, or any legally binding agreement in connection or at any time relevant to such Exploit;
   - iv. such person has fully complied with the requirements of Section 2.4 with respect to such Exploit;
   - v. the Reward comprises such person's sole direct and indirect compensation, reward, and benefit in connection with the Exploit; and
   - vi. such person has complied with the Mainnet Disclosure Prohibition in Section 2.2(c).

e. **Eligible Stress Test Exploit**. An "**Eligible Stress Test Exploit**" is an Exploit and related actions or transactions that, taken together:
   - i. are conducted during a Declared Attack Period (i.e., while the target contracts are in `UNDER_ATTACK` or `PROMOTION_REQUESTED` state);
   - ii. result in the complete transfer of all Returnable Assets (or the transfer of all Returnable Assets, minus the applicable Bounty) to the Asset Recovery Address as promptly as reasonably practicable during or after such Exploit;
   - iii. have been performed in good faith solely for the purposes of testing the Protocol's security and earning the Reward;
   - iv. are not conducted in a negligent, reckless, or fraudulent manner and do not constitute an intentional, knowing, reckless, or negligent breach of any applicable or otherwise relevant law, legal order, or any legally binding agreement;
   - v. comply with the Mainnet Disclosure Prohibition in Section 2.2(c); and
   - vi. otherwise comply with and satisfy all applicable terms and conditions of this Agreement.

f. **Eligible Rescue Exploit**. An "**Eligible Rescue Exploit**" is an Exploit and related actions or transactions that, taken together:
   - i. are conducted during an Urgent Blackhat Exploit;
   - ii. are conducted with the primary intent to rescue, secure, or preserve Assets that would otherwise be stolen or lost due to the Urgent Blackhat Exploit;
   - iii. result in the complete transfer of all Returnable Assets (or the transfer of all Returnable Assets, minus the applicable Bounty) to the Asset Recovery Address (or, if no Asset Recovery Address has been designated, to a reasonable alternative address for the benefit of the Protocol or its Users) as promptly as reasonably practicable;
   - iv. are not conducted in a negligent, reckless, or fraudulent manner;
   - v. comply with the Mainnet Disclosure Prohibition in Section 2.2(c); and
   - vi. otherwise comply with and satisfy all applicable terms and conditions of this Agreement.

g. **Urgent Blackhat Exploit**. An "**Urgent Blackhat Exploit**" means an ongoing or imminent Exploit of a Protocol by a Blackhat that, absent intervention, is reasonably likely to result in material loss of Assets to the Protocol or its Users. Evidence of an Urgent Blackhat Exploit may include, but is not limited to:
   - i. on-chain transactions showing unauthorized movement of Assets;
   - ii. pending mempool transactions that would result in theft if executed;
   - iii. public disclosure of a critical vulnerability being actively exploited;
   - iv. detection of malicious contract deployments targeting the Protocol.

h. **Declared Attack Period**. "**Declared Attack Period**" means the period during which the AttackRegistry returns either `ContractState.UNDER_ATTACK` or `ContractState.PROMOTION_REQUESTED` for the relevant contract addresses.

i. **Covered Period**. "**Covered Period**" means any period during which Eligible Exploits are authorized under this Agreement, including both Declared Attack Periods and Urgent Blackhat Exploits.

#### 2.4 Required Procedures for Eligible Exploits

##### 2.4.1 Procedures for Stress Test Exploits (Declared Attack Period)

a. **Verification of Contract State**. Before attempting a Stress Test Exploit, the Whitehat shall verify that `isUnderAttack` returns `true` for the target contracts by calling this function on the AttackRegistry. The Whitehat shall not proceed with a Stress Test Exploit if `isUnderAttack` returns `false`.

b. **Consent to Exploit**. During a Declared Attack Period, the Protocol Community hereby grants consent to Eligible Whitehats to conduct Stress Test Exploits against the contracts in scope, as specified during the DAO Adoption Procedures.

c. **Notification of Stress Test Exploit**.
   - i. The Whitehat shall use commercially reasonable efforts to notify the Protocol Community that the Whitehat is attempting or has completed a Stress Test Exploit as soon as reasonably practicable, using the contact details provided during adoption.
   - ii. Notification is strongly recommended but not required prior to initiating an Exploit. Notification IS required upon completion of an Exploit.

##### 2.4.2 Procedures for Rescue Exploits (Urgent Blackhat Exploit)

a. **Determination of Urgent Blackhat Exploit**. Before attempting a Rescue Exploit, the Whitehat should, to the extent reasonably practicable under the circumstances, verify that an Urgent Blackhat Exploit is occurring or imminent. Given the time-sensitive nature of such situations, this determination may be made in real-time based on available evidence.

b. **Implied Consent**. During an Urgent Blackhat Exploit, the Protocol Community is deemed to have granted implied consent for Eligible Whitehats to conduct Rescue Exploits to secure Assets that would otherwise be stolen.

c. **Notification of Rescue Exploit**.
   - i. The Whitehat shall notify the Protocol Community as soon as reasonably practicable after initiating or completing a Rescue Exploit.
   - ii. If contact details were provided during DAO Adoption Procedures, those shall be used. Otherwise, the Whitehat shall use commercially reasonable efforts to contact the Protocol Community through any available means.
   - iii. The notification should include evidence of the Urgent Blackhat Exploit that triggered the Rescue Exploit.

##### 2.4.3 Common Procedures for All Eligible Exploits

d. **Transfer of Assets to Asset Recovery Address**.
   - i. The Whitehat shall at all times use best efforts to secure, and preserve the value of, all Exploited Assets.
   - ii. Upon removing, appropriating, diverting, or otherwise obtaining custody or control over any Exploited Assets, the Whitehat must use best efforts to transfer them to the Asset Recovery Address as promptly as reasonably practicable, as follows:
      - A. If the Adoption Procedures for the relevant Protocol expressly allow for the Whitehat to deduct and retain the Bounty from the Exploited Assets, then the Whitehat shall transfer all Returnable Assets minus the applicable Bounty into the Asset Recovery Address as promptly as reasonably practicable.
      - B. If the Adoption Procedures for the relevant Protocol do not expressly allow for the Whitehat to deduct and retain the Bounty from the Exploited Assets, or if no Adoption Procedures were completed (e.g., for Rescue Exploits under default coverage), then the Whitehat shall transfer all Returnable Assets into the Asset Recovery Address as promptly as reasonably practicable.
      - C. For Rescue Exploits where no Asset Recovery Address was designated, the Whitehat shall transfer Returnable Assets to a reasonable alternative address for the benefit of the Protocol or its Users, such as the Protocol's treasury, a multisig controlled by the Protocol team, or a similar secure address.
   - iii. An Exploit with respect to which the Returnable Assets have not been so transferred shall not constitute an Eligible Exploit and the Whitehat shall not be entitled to any Reward with respect thereto.
   - iv. If a Whitehat is unable to transfer the Returnable Assets within six hours of obtaining custody or control over them, then the Whitehat must notify the Protocol Community of their continued intention to transfer the Returnable Assets and the reasons for the delay.

e. **Exploited Assets**. "**Exploited Assets**" means, with respect to a given Exploit, all Tokens that, directly or indirectly in connection with such Exploit, have been in whole or in part removed, appropriated, diverted, or otherwise obtained by or on behalf of a Whitehat from the Protocol.

f. **Asset Recovery Address**. "**Asset Recovery Address**" means the blockchain network address to which Eligible Whitehats shall deposit the Returnable Assets, as specified during the DAO Adoption Procedures, or, for Protocols that have not completed DAO Adoption Procedures, a reasonable alternative address for the benefit of the Protocol or its Users.

g. **Returnable Assets**. "**Returnable Assets**" means, with respect to a given Exploit, all of the Exploited Assets recovered by a Whitehat, minus any Exploited Assets utilized by the Whitehat in good faith, arms-length transactions to pay transaction fees or costs necessary to perform the Exploit and return Exploited Assets to the Asset Recovery Address, provided that in each case the Whitehat used best efforts to minimize such fees and costs.

---

### 3. Eligibility, Release, and Bounty

#### 3.1 Eligibility Conditions

a. **Conditions Precedent**. Each clause of the terms "Eligible Whitehat" and "Eligible Exploit" (whether Eligible Stress Test Exploit or Eligible Rescue Exploit), and the fulfillment of each applicable requirement, shall be conditions precedent to any person's entitlement to receive a Reward.

b. **Relationship of Protocol Community to Whitehat**. Under no circumstances do the Protocol Community or any Protocol Community Member seek through this Agreement to facilitate, encourage, or condone any conduct by Whitehat that violates any Legal Requirement under any applicable jurisdiction. The Protocol Community disclaims any liability or direct or consequential damages caused by Whitehat by participating in the Program.

#### 3.2 Bounty

a. **Bounty for Stress Test Exploits**. For Eligible Stress Test Exploits, the "**Bounty**" means Tokens equal in US Dollar value to the lesser of:
   - i. the bountyPercentage (specified during the DAO Adoption Procedures, recommended 10%) of the US Dollar value of Returnable Assets recovered by each Eligible Whitehat and transferred to the Asset Recovery Address; or
   - ii. the bountyCapUSD (specified during the DAO Adoption Procedures, recommended $5,000,000).

b. **Bounty for Rescue Exploits**. For Eligible Rescue Exploits where no Adoption Procedures were completed, the "**Bounty**" means Tokens equal in US Dollar value to the lesser of:
   - i. 10% of the US Dollar value of Returnable Assets recovered by each Eligible Whitehat and transferred to the Asset Recovery Address (or reasonable alternative); or
   - ii. $5,000,000 USD.

   If the Protocol Community had completed Adoption Procedures specifying different bounty terms, those terms shall apply to Rescue Exploits as well.

c. **Payment of Bounty**. Following the completion of an Eligible Exploit and the determination that the Whitehat is eligible for a Reward pursuant to the terms of this Agreement:
   - i. If the Whitehat has returned all of the Returnable Assets, the Protocol Community will pay the Bounty to the Whitehat, subject to the terms of this Agreement. Payment is to be made to the Whitehat's address as nominated at the time of delivery of the Returnable Assets to the Asset Recovery Address.
   - ii. The Protocol Community shall transfer the Bounty within a reasonable time, and in no event more than 15 calendar days after the date that the Returnable Assets are sent to the Asset Recovery Address.
   - iii. If the Adoption Procedures allow for Retained Bounty, and the Whitehat has retained the Bounty, the Whitehat shall verify in writing to the Protocol Community the address at which the Retained Bounty is located.
   - iv. For Rescue Exploits where no Adoption Procedures were completed, Whitehats should NOT retain Bounty from Exploited Assets without prior written agreement from the Protocol Community.

#### 3.3 Reward Dispute Procedures

a. In the event of a dispute regarding the Bounty amount or Whitehat eligibility:
   - i. If the dispute relates to the value of tokens only, each Party shall appoint an appraiser within 30 calendar days;
   - ii. If the dispute relates to eligibility, the Arbitration provisions of Section 7.1(b) shall apply.

---

### 4. Certain Covenants and Agreements of Whitehat

#### 4.1 Legal Compliance

Whitehat shall at all times ensure that their actions are in compliance with all applicable Legal Requirements. Whitehat acknowledges that Protocol Community will not, and has no legal obligation to, monitor the legal compliance of Whitehat.

#### 4.2 Mainnet Responsibility

**CRITICAL COVENANT**: Whitehat covenants and agrees that:

a. Whitehat shall NOT exploit any vulnerability discovered on BattleChain on any other blockchain network, including but not limited to Ethereum mainnet;

b. Whitehat shall NOT share, sell, disclose, or otherwise communicate any vulnerability information to any third party who might use such information to exploit contracts on other networks;

c. Whitehat shall promptly notify the Protocol Community of any vulnerabilities that may affect deployments on other networks;

d. Whitehat understands and acknowledges that the same or similar code deployed on BattleChain may also be deployed on other networks;

e. Breach of this Section 4.2 shall result in immediate forfeiture of all rights and protections under this Agreement.

#### 4.3 Non-Exclusivity

Whitehat acknowledges and agrees that there shall be no relationship of exclusivity between Whitehat and Protocol Community.

#### 4.4 No Partnership, Agency, or Similar Relationship

Whitehat shall not be deemed to be part of any partnership, joint venture, unincorporated association, or other Entity with Protocol Community. Whitehat shall not be deemed an employee, independent contractor, or other Representative of the Protocol Community.

#### 4.5 No Guarantees or Assurances of Rewards

Protocol Community shall not be deemed to be providing any express or implied guarantee that Whitehat will receive any Rewards.

---

### 5. Representations and Warranties of Whitehat

Whitehat hereby represents and warrants to and for the benefit of Protocol Community and Protocol Community Members:

#### 5.1 Authority and Due Execution

a. Whitehat has all requisite capacity, power, and authority to enter into, and perform Whitehat's obligations under, this Agreement.

b. This Agreement has been duly accepted by Whitehat and constitutes the legal, valid, and binding obligation of Whitehat.

#### 5.2 Money Laundering and Sanctions

To the best of Whitehat's knowledge, any crypto-assets or funds used by Whitehat in any Eligible Exploit were not derived from any activities that contravene any law. Whitehat is not:
- i. named on an OFAC list or subject to sanctions under OFAC or any other sanctions regime;
- ii. a senior foreign political figure or immediate family member thereof.

#### 5.3 Non-Contravention

The execution and delivery of this Agreement does not conflict with any applicable Legal Requirement or any material contract or agreement of Whitehat.

#### 5.4 Whitehat's Independent Investigation and Non-Reliance

Whitehat is sophisticated, experienced, and knowledgeable in blockchain security. Whitehat has conducted an independent investigation of the Protocol, the Program, and the matters contemplated by this Agreement.

#### 5.5 Litigation

There is no Legal Proceeding pending or threatened that involves Whitehat and is related to exploits of software or blockchain technologies.

#### 5.6 Intellectual Property

Whitehat owns or has valid licenses for all Intellectual Property Rights used in the course of any Eligible Exploit.

#### 5.7 Compliance

Whitehat has complied with all applicable Legal Requirements relating to blockchain technologies and cybersecurity activities.

#### 5.8 Understanding of BattleChain Environment

Whitehat represents and warrants that:
- i. Whitehat understands that BattleChain is a production blockchain with real funds that provides enhanced freedom for security testing;
- ii. Whitehat understands that vulnerabilities discovered on BattleChain may exist on other networks;
- iii. Whitehat will NOT exploit or disclose vulnerabilities on any network other than BattleChain during a Covered Period;
- iv. Whitehat will follow responsible disclosure procedures for any cross-chain vulnerabilities.

---

### 6. Releases

#### 6.1 Mutual Release Among Protocol Community and Protocol Community Members

a. **Release**. The Protocol Community and each Protocol Community Member hereby release each other from every Claim relating to or arising out of this Agreement or any Eligible Exploit.

b. **No-Litigation**. The Protocol Community and each Protocol Community Member agree not to assert against each other any Claim described above.

#### 6.2 Release of Whitehat Liability to Protocol Community

a. **Release by Protocol Community**. The Protocol Community and each Protocol Community Member hereby release Whitehat from every Claim relating to or arising out of each Eligible Exploit successfully executed by the Whitehat; **provided, however**, that:
   - i. Whitehat shall not be released from any breach of this Agreement;
   - ii. Whitehat shall not be released from any violation of the Mainnet Disclosure Prohibition in Section 2.2(c);
   - iii. Whitehat shall not be released from any indemnity owed under Section 7.1(a).

b. **No-Litigation**. The Protocol Community and each Protocol Community Member agree not to assert against the Whitehat any Claim from which such Whitehat has been released under this Section.

c. **Scope Limitation**. This release applies ONLY to Eligible Exploits conducted on BattleChain during a Covered Period. It does NOT apply to:
   - i. Exploits on any blockchain other than BattleChain;
   - ii. Exploits on BattleChain that do not qualify as either:
      - A. Stress Test Exploits during a Declared Attack Period (contracts in `UNDER_ATTACK` state); or
      - B. Rescue Exploits during an Urgent Blackhat Exploit;
   - iii. Disclosure or exploitation of vulnerabilities on other networks.

#### 6.3 Release by Whitehat

a. Whitehat hereby releases each Protocol Community Person from every Claim relating to participation in the Program, except for rights expressly provided to Whitehat under this Agreement.

---

### 7. Indemnification and Arbitrable Disputes

#### 7.1 Indemnification

a. **Indemnity**. Whitehat shall hold harmless and indemnify Protocol Community, Protocol Community Members, their Affiliates, and their respective Representatives (collectively, the "**Indemnitees**") from and against any Damages arising from:
   - i. any material misrepresentation in Whitehat's representations and warranties;
   - ii. any material breach of this Agreement by Whitehat;
   - iii. any violation of the Mainnet Disclosure Prohibition; or
   - iv. any exploit conducted by Whitehat outside of a Covered Period or on any network other than BattleChain.

   The aggregate maximum amount of indemnity shall be limited to the amount of Bounty received by the Whitehat, EXCEPT for violations of clauses (iii) and (iv), which shall have no cap.

b. **Arbitrable Disputes**. Disputes shall be settled by binding arbitration in Singapore under SIAC rules, as detailed in the original agreement structure.

---

### 8. Term and Termination

#### 8.1 Term for Declared Attack Period Coverage

For Declared Attack Period (Stress Test Exploit) coverage, this Agreement applies to a Protocol Community from the date when the Protocol Community's call to `requestUnderAttack` is approved (i.e., `approveAttack` is called by the Registry Moderator), and terminates when the Protocol's contracts transition to `PRODUCTION` state. The Declared Attack Period includes both the `UNDER_ATTACK` and `PROMOTION_REQUESTED` states - Whitehats may conduct Stress Test Exploits throughout the promotion delay period defined by the AttackRegistry.

#### 8.2 Term for Urgent Blackhat Exploit Coverage

For Urgent Blackhat Exploit (Rescue Exploit) coverage, this Agreement applies by default to all Protocols deployed on BattleChain, unless the Protocol Community has explicitly opted out. This coverage continues indefinitely for each Protocol, regardless of the Protocol's state in the AttackRegistry.

#### 8.3 Survival

Termination of Declared Attack Period coverage shall not affect:
- Rights and obligations with respect to Eligible Exploits completed before termination;
- Urgent Blackhat Exploit coverage, which continues independently;
- The Mainnet Disclosure Prohibition, which survives indefinitely.

---

### 9. Miscellaneous Provisions

#### 9.1 Amendments

This Agreement may be amended by the BattleChain governance with at least 45 days advance written notice published on BattleChain's official communication channels.

#### 9.2 Governing Law

This Agreement shall be governed by and construed in accordance with the laws of Singapore.

#### 9.3 Notices

Notices to Protocol Community shall be sent to the contact details provided during adoption. Notices to Whitehat shall be sent to any address used by Whitehat in connection with a Stress Test Exploit.

#### 9.4 Severability

If any provision is determined to be invalid or unenforceable, the remainder of this Agreement shall continue in full force and effect.

#### 9.5 Waiver of Class-Action Rights

Each Party waives the right to litigate any dispute as a class action.

#### 9.6 Waiver of Jury Trial

Each Party waives any right to trial by jury.

---

## Exhibit A: Certain Defined Terms

For purposes of this Agreement, the following capitalized terms have the definitions ascribed to them:

- **"Affiliate"** means a Person that directly or indirectly controls, is controlled by, or is under common control with another Person.

- **"agreementURI"** means a Uniform Resource Identifier pointing to the text of this Agreement. The URI may use any IANA-registered scheme including IPFS (ipfs://), HTTPS (https://), data URIs with base64 encoding per RFC 4648, or Ethereum-based schemes per EIP-681/EIP-831.

- **"Assets"** means the crypto-assets transacted on or in connection with an Eligible Exploit.

- **"AttackRegistry"** means the BattleChain system contract that tracks contract states and manages the Declared Attack Period lifecycle. The AttackRegistry defines key parameters including `PROMOTION_WINDOW` and `PROMOTION_DELAY`.

- **"Blackhat"** means any Person who conducts or attempts to conduct an Exploit with the intent to steal, misappropriate, or permanently deprive the Protocol or its Users of Assets.

- **"BattleChain"** means the ZKsync-stack production Layer 2 blockchain with real funds, designed to provide enhanced security for protocols by giving Whitehats more freedom and incentive to identify vulnerabilities.

- **"Claim"** means all disputes, claims, controversies, demands, rights, obligations, liabilities, actions, and causes of action of every kind.

- **"ContractState"** means the enumerated states tracked by the AttackRegistry: NOT_DEPLOYED, NEW_DEPLOYMENT, ATTACK_REQUESTED, UNDER_ATTACK, PROMOTION_REQUESTED, PRODUCTION.

- **"Damages"** means any loss, damage, injury, decline in value, lost opportunity, Liability, claim, demand, settlement, judgment, award, fine, penalty, tax, fee, charge, costs, or expense of any nature.

- **"Covered Period"** means any period during which Eligible Exploits are authorized under this Agreement, including both Declared Attack Periods and Urgent Blackhat Exploits.

- **"Declared Attack Period"** means the period during which a Protocol's contracts are in the `UNDER_ATTACK` or `PROMOTION_REQUESTED` state.

- **"Eligible Exploit"** means either an Eligible Stress Test Exploit or an Eligible Rescue Exploit.

- **"Entity"** means any corporation, partnership, joint venture, trust, company, firm, or other enterprise, association, organization, or entity.

- **"Governmental Entity"** means any nation, government, or governmental Entity, authority, or instrumentality.

- **"Intellectual Property Rights"** means any and all rights in intellectual property anywhere in the world.

- **"Legal Proceeding"** means any action, suit, litigation, arbitration, claim, proceeding, hearing, inquiry, audit, examination, or investigation.

- **"Legal Requirement"** means any law, statute, constitution, treaty, directive, resolution, ordinance, code, rule, regulation, judgment, or requirement issued by any Governmental Entity.

- **"Liability"** means any debt, obligation, duty, or liability of any nature.

- **"Mainnet"** means Ethereum mainnet or any other production blockchain network.

- **"Parties"** means the Protocol Community, Protocol Community Members, and Whitehats participating in the Program.

- **"Person"** means any individual, Entity, or Governmental Entity.

- **"Program"** means the BattleChain Safe Harbor Program as set out in this Agreement.

- **"Representatives"** means a Person's officers, directors, employees, agents, attorneys, accountants, advisors, and representatives.

- **"Rescue Exploit"** means an Exploit conducted during an Urgent Blackhat Exploit with the intent to secure Assets that would otherwise be stolen.

- **"Responsible Disclosure"** means the practice of privately notifying a Protocol Community of a vulnerability and allowing reasonable time for remediation before any public disclosure.

- **"Stress Test Exploit"** means an Exploit conducted during a Declared Attack Period for the purpose of testing a Protocol's security.

- **"Technology"** means any technology, formulae, algorithms, procedures, processes, methods, techniques, ideas, know-how, software, and related materials.

- **"Urgent Blackhat Exploit"** means an ongoing or imminent Exploit of a Protocol by a Blackhat that, absent intervention, is reasonably likely to result in material loss of Assets to the Protocol or its Users.

- **"Whitehat"** means any Person who conducts or attempts to conduct an Exploit with the intent to secure Assets for the benefit of the Protocol or its Users.

---

## Exhibit B: Attack Moderator Adoption Procedures

When calling `requestUnderAttack` on the AttackRegistry, the Attack Moderator should ensure:

1. **Protocol Information**: The protocol name and scope are clearly documented
2. **Asset Recovery Address**: A secure address is designated for receiving Returnable Assets
3. **Contact Details**: Valid contact information is provided for Whitehat notifications
4. **Bounty Terms**: Clear bounty parameters are established:
   - Bounty Percentage (recommended: 10%)
   - Bounty Cap (recommended: $5,000,000 USD)
   - Whether Retained Bounty is permitted
   - Identity requirements for payment
5. **Agreement URI**: A URI pointing to this Agreement is stored for reference (may use IPFS, HTTPS, data URI, or any IANA-registered scheme)
6. **User Notification**: Protocol users are notified of the transition to `UNDER_ATTACK` state

---

## Exhibit C: User Adoption Procedures

**TO BE INSERTED INTO TERMS OF SERVICE FOR PROTOCOL WEB APPLICATIONS:**

The User hereby acknowledges and agrees to the BattleChain Safe Harbor Agreement. The User understands that:

- While contracts are in `UNDER_ATTACK` or `PROMOTION_REQUESTED` state (Declared Attack Period), Whitehats may conduct Stress Test Exploits
- During an Urgent Blackhat Exploit (active malicious attack), Whitehats may conduct Rescue Exploits to secure funds
- Tokens deposited by User may be subject to Exploits and Bounty deductions during any Covered Period
- Tokens may be lost, stolen, or suffer diminished value during a Covered Period
- Payment of Bounties may constitute a taxable disposition by the User
- User agrees to hold Protocol Community Members harmless from losses during any Covered Period

---

## Exhibit D: Whitehat Risk Disclosures

Participation in the BattleChain Safe Harbor Program carries significant risk. You should carefully consider:

### Two Types of Covered Exploits

This Agreement covers two types of Eligible Exploits:
1. **Stress Test Exploits** - conducted during a Declared Attack Period (contracts in `UNDER_ATTACK` or `PROMOTION_REQUESTED` state)
2. **Rescue Exploits** - conducted during an Urgent Blackhat Exploit (active malicious attack in progress)

### Verify Before Acting

**For Stress Test Exploits:** You MUST verify that `isUnderAttack` returns `true` for target contracts by calling this function on the AttackRegistry before conducting any Exploit.

**For Rescue Exploits:** You should verify that an actual Urgent Blackhat Exploit is occurring or imminent. You bear the burden of proving that an attack was in progress.

### BattleChain Only

This Agreement covers ONLY exploits on BattleChain. You have NO protection for exploits on any other network.

### Mainnet Vulnerability Disclosure

If you discover a vulnerability that affects mainnet deployments:
- You MUST NOT exploit it on mainnet
- You MUST NOT share it with anyone who might exploit it
- You SHOULD notify the Protocol Community for potential additional bounty
- Violation may result in criminal prosecution and forfeiture of all rights under this Agreement

### No Guarantee of Reward

Even if you successfully complete an Eligible Exploit, there is no guarantee you will receive a Reward if you violate any terms of this Agreement.

### Criminal Liability

This Agreement cannot protect you from criminal prosecution. Exploits outside the scope of this Agreement may constitute computer fraud.

### Tax Liability

You are responsible for any tax liability from receiving Bounties.

### Arbitration

Disputes must be arbitrated in Singapore under SIAC rules. You waive any right to jury trial or class action.

---

## Exhibit E: Protocol FAQ

### What is BattleChain?

BattleChain is a production Layer 2 blockchain built on the ZKsync stack with real funds. It provides enhanced security for protocols by giving Whitehats more freedom and incentive to identify vulnerabilities, while protecting them through this Safe Harbor Agreement.

### What two types of protection does this Agreement provide?

1. **Declared Attack Period (Stress Test) Protection**: For protocols that voluntarily opt-in via `requestUnderAttack`, Whitehats can conduct Stress Test Exploits during the `UNDER_ATTACK` and `PROMOTION_REQUESTED` states.

2. **Urgent Blackhat Exploit (Rescue) Protection**: For ALL protocols on BattleChain (by default), Whitehats can conduct Rescue Exploits when an active malicious attack is in progress, regardless of contract state.

### How does a protocol enter the Stress Test Program?

1. Deploy contracts on BattleChain (they start in `NEW_DEPLOYMENT` state)
2. Call `requestUnderAttack` on the AttackRegistry within the `PROMOTION_WINDOW` period
3. Wait for Registry Moderator approval via `approveAttack`
4. Contracts enter `UNDER_ATTACK` state - Whitehats may now conduct Stress Test Exploits

### How does a protocol exit the Stress Test Program?

1. Call `promote` on the AttackRegistry
2. Wait for the `PROMOTION_DELAY` period (or receive `instantPromote` from Registry Moderator)
3. Contracts enter `PRODUCTION` state - no more Stress Test Exploits authorized
4. Note: Rescue Exploit protection continues even after entering `PRODUCTION` state

### What happens if our protocol is attacked while in PRODUCTION state?

The Agreement provides default Urgent Blackhat Exploit coverage for all BattleChain protocols. If a Whitehat front-runs a Blackhat to rescue your funds, they are protected under this Agreement and entitled to the default bounty (10%, capped at $5M).

### What happens if a whitehat finds a mainnet vulnerability?

The whitehat MUST:
- NOT exploit it on mainnet
- NOT share the information with potential attackers
- Notify the Protocol Community via provided contact details

The whitehat MAY be eligible for additional bounties for responsible disclosure.

### What bounty is recommended?

- 10% of Returnable Assets
- Capped at $5,000,000 USD
- These are recommendations; Protocol Communities may set different terms during Adoption Procedures
- For Rescue Exploits where no Adoption Procedures were completed, the default 10%/$5M applies

---

**BY CONDUCTING AN ELIGIBLE EXPLOIT ON BATTLECHAIN, YOU ARE ENTERING INTO AND CONSENTING TO BE BOUND BY THIS AGREEMENT.**

**NOTICE TO WHITEHAT: IF YOU DO NOT ABIDE BY ALL TERMS OF THIS AGREEMENT, INCLUDING THE MAINNET DISCLOSURE PROHIBITION, YOU MAY FAIL TO BE ELIGIBLE FOR ANY RIGHTS OR BENEFITS UNDER THIS AGREEMENT AND MAY BE SUBJECT TO LEGAL ACTION.**

---

*Contact: safeharbor@battlechain.com*

*This Agreement is dual-licensed under the MIT License and Apache License 2.0. You may choose either license at your option.*
