// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.24;

interface IBattleChainSafeHarborRegistry {
    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Set the agreement factory address
    /// @param factory The new agreement factory address
    function setAgreementFactory(address factory) external;

    /// @notice Records the caller's adopted Safe Harbor agreement.
    /// @dev Authoritative for Eligible Funds Rescue (Urgent Blackhat Exploit) coverage only;
    ///      it does NOT bind which agreement governs an Eligible Stress Test Exploit — for
    ///      attack-mode coverage the Binding Agreement is resolved via AttackRegistry.
    /// @param agreementAddress The agreement to adopt for msg.sender.
    function adoptSafeHarbor(address agreementAddress) external;

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the agreement the adopter recorded via `adoptSafeHarbor`. This is
    ///         authoritative for Eligible Funds Rescue (Urgent Blackhat Exploit) coverage but
    ///         NOT for Eligible Stress Test Exploits — for attack-mode coverage, resolve the
    ///         Binding Agreement via AttackRegistry (see the legal text Section 2.3(b)(6)).
    ///         The two registries can diverge.
    /// @param adopter The adopter to query.
    /// @return The agreement address recorded for the adopter.
    function getAgreement(address adopter) external view returns (address);

    /// @notice Function that returns if a chain is valid.
    /// @param caip2ChainId The CAIP-2 ID of the chain to check.
    /// @return bool True if the chain is valid, false otherwise.
    function isChainValid(string calldata caip2ChainId) external view returns (bool);

    /// @notice Checks that the agreement was created by this registry's configured factory.
    ///         Returns true for ANY factory-deployed agreement — a `true` return does not
    ///         establish that the agreement binds any specific contract or that its terms
    ///         govern any whitehat activity. Do not use as a substitute for resolving the
    ///         Binding Agreement via AttackRegistry.
    /// @param agreementAddress The agreement address to check.
    /// @return True if the agreement was created by the configured factory.
    function isAgreementValid(address agreementAddress) external view returns (bool);

    /// @notice Get the agreement factory address
    /// @return The agreement factory address
    function getAgreementFactory() external view returns (address);

    /// @notice Get the attack registry address
    /// @return The attack registry address
    function getAttackRegistry() external view returns (address);
}
