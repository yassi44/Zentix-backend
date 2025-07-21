// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title ZentixVault
 * @notice Coffre d'épargne automatisé USDC avec intégration Aave v3 et système d'XP
 * 
 */
contract ZentixVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @dev USDC a 6 décimales (USDC)
    uint256 private constant USDC_DECIMALS = 6;

    /// @dev Dépôt minimum : 50 USDC
    uint256 public constant MIN_DEPOSIT = 50 * 10 ** USDC_DECIMALS;

    /// @dev Dépôt maximum : 5000 USDC
    uint256 public constant MAX_DEPOSIT = 5000 * 10 ** USDC_DECIMALS;

    /// @dev Frais fixes par dépôt : 1 USDC
    uint256 public constant DEPOSIT_FEE = 1 * 10 ** USDC_DECIMALS;

    /// @dev Récompense XP par dépôt
    uint256 public constant XP_PER_DEPOSIT = 10;

    /// @dev Code de parrainage Aave pour Zentix
    uint16 private constant AAVE_REFERRAL_CODE = 99;

    /// @dev Frais fixes par retrait : 1 USDC
    uint256 public constant WITHDRAWAL_FEE = 1 * 10 ** USDC_DECIMALS;

    /// @notice Contrat du token USDC
    IERC20 public usdc;

    /// @notice Contrat Pool Aave v3
    IPool public aavePool;

    /// @notice Adresse du token aUSDC (reçu depuis Aave)
    address public aUSDC;

    /// @notice Indique si la fonctionnalité de réclamation est activée
    bool public claimEnabled;

    /// @notice Mapping des adresses utilisateurs vers leur solde XP
    mapping(address => uint256) public xp;

    /// @notice Mapping des adresses utilisateurs vers leur montant total déposé
    mapping(address => uint256) public userDeposits;

    /// @notice Mapping des adresses utilisateurs vers leur statut de réclamation
    mapping(address => bool) public hasClaimed;

    /// @notice Mapping des adresses autorisées à appeler la fonction de réclamation (ex : contrats tokens)
    mapping(address => bool) public authorizedClaimers;

    /// @notice Total des frais collectés par le contrat
    uint256 public totalFeesCollected;

    /// @notice Montant total déposé par tous les utilisateurs
    uint256 public totalDeposited;

    /// @notice XP total distribué
    uint256 public totalXPDistributed;

    /**
     * @notice Émis lorsqu'un utilisateur effectue un dépôt
     * @param user Adresse de l'utilisateur effectuant le dépôt
     * @param amount Montant brut déposé (frais inclus)
     * @param netAmount Montant net investi sur Aave (après frais)
     * @param fee Frais prélevés sur le dépôt
     * @param xpEarned XP gagné lors de ce dépôt
     * @param newXPBalance Nouveau solde XP de l'utilisateur
     */
    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 netAmount,
        uint256 fee,
        uint256 xpEarned,
        uint256 newXPBalance
    );

    /**
     * @notice Émis lorsqu'un utilisateur effectue un retrait du coffre
     * @param user Adresse de l'utilisateur effectuant le retrait
     * @param grossAmount Montant brut retiré d'Aave (avant frais)
     * @param fee Frais prélevés sur le retrait
     * @param netAmount Montant net reçu par l'utilisateur (après frais)
     * @param xpEarned XP gagné lors de ce retrait
     * @param newXPBalance Nouveau solde XP de l'utilisateur
     * @param recipient Adresse recevant les fonds retirés
     */
    event Withdrawal(
        address indexed user,
        uint256 grossAmount,
        uint256 fee,
        uint256 netAmount,
        uint256 xpEarned,
        uint256 newXPBalance,
        address indexed recipient
    );

    /**
     * @notice Émis lorsqu'un utilisateur réclame ses récompenses
     * @param user Adresse de l'utilisateur réclamant
     * @param claimer Adresse ayant initié la réclamation (peut être un autre contrat)
     */
    event Claimed(address indexed user, address indexed claimer);

    /**
     * @notice Émis lors de la mise à jour du statut de réclamation
     * @param enabled Indique si la réclamation est activée ou désactivée
     */
    event ClaimStatusUpdated(bool enabled);

    /**
     * @notice Émis lorsqu'une adresse est autorisée ou non à réclamer
     * @param claimer Adresse autorisée/désautorisée
     * @param authorized Indique si l'adresse est maintenant autorisée ou non
     */
    event ClaimerAuthorizationUpdated(address indexed claimer, bool authorized);

    /// @notice Erreur : montant du dépôt trop faible
    error DepositTooLow();
    /// @notice Erreur : montant du dépôt trop élevé
    error DepositTooHigh();
    /// @notice Erreur : montant de retrait invalide
    error InvalidWithdrawalAmount();
    /// @notice Erreur : la réclamation est désactivée
    error ClaimDisabled();
    /// @notice Erreur : l'utilisateur a déjà réclamé
    error AlreadyClaimed();
    /// @notice Erreur : l'utilisateur n'a pas d'XP à réclamer
    error NoXPToClaim();
    /// @notice Erreur : l'appelant n'est pas autorisé à réclamer
    error NotAuthorizedToClaim();
    /// @notice Erreur : tentative d'autoriser l'adresse zéro
    error InvalidClaimerAddress();
    /// @notice Erreur : solde insuffisant pour le retrait + frais
    error InsufficientBalanceForWithdrawal();
    /// @notice Erreur : l'adresse USDC ne peut pas être nulle
    error UsdcAddressZero();
    /// @notice Erreur : l'adresse du pool Aave ne peut pas être nulle
    error AavePoolAddressZero();
    /// @notice Erreur : l'adresse aUSDC introuvable
    error AUSDCAddressNotFound();
    /// @notice Erreur : le destinataire ne peut pas être l'adresse zéro
    error RecipientZeroAddress();
    /// @notice Erreur : aucun frais à retirer
    error NoFeesToWithdraw();

    constructor(address _usdc, address _aavePool) Ownable(msg.sender) {
        require(
            _usdc != address(0),
            "ZentixVault: USDC address cannot be zero"
        );
        require(
            _aavePool != address(0),
            "ZentixVault: Aave Pool address cannot be zero"
        );

        usdc = IERC20(_usdc);
        aavePool = IPool(_aavePool);

        // Récupère l'adresse aUSDC depuis Aave
        DataTypes.ReserveData memory reserveData = aavePool.getReserveData(
            _usdc
        );
        aUSDC = reserveData.aTokenAddress;
        require(aUSDC != address(0), "ZentixVault: aUSDC address not found");

        // Approuve le pool Aave pour gérer un montant très élevé d’USDC (quasi illimité)
        usdc.approve(_aavePool, type(uint256).max);

        // Approve le AavePool pour pouvoir retirer les aUSDC 
        IERC20(aUSDC).approve(address(_aavePool), type(uint256).max);

        // La réclamation est désactivée par défaut
        claimEnabled = false;
    }

    /**
     * @notice Dépose de l'USDC dans le coffre, prélève des frais et investit le reste sur Aave v3
     * @param amount Montant d'USDC à déposer (doit être entre MIN_DEPOSIT et MAX_DEPOSIT)
     * @dev Approuve automatiquement Aave pour dépenser l'USDC et le fournit au pool
     *      Attribue XP_PER_DEPOSIT XP à l'utilisateur
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount < MIN_DEPOSIT) revert DepositTooLow();
        if (amount > MAX_DEPOSIT) revert DepositTooHigh();

        // Transfert l'USDC de l'utilisateur vers ce contrat
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Calcule le montant net après frais
        uint256 netAmount = amount - DEPOSIT_FEE;

        // Met à jour la comptabilité
        totalFeesCollected += DEPOSIT_FEE;
        totalDeposited += netAmount;
        userDeposits[msg.sender] += netAmount;

        // Attribue l'XP
        xp[msg.sender] += XP_PER_DEPOSIT;
        totalXPDistributed += XP_PER_DEPOSIT;

        // Approuve Aave pour dépenser l'USDC
        usdc.approve(address(aavePool), netAmount);

        // Fournit l'USDC à Aave v3 pour ce contrat
        aavePool.supply(
            address(usdc),
            netAmount,
            address(this),
            AAVE_REFERRAL_CODE
        );

        emit Deposit(
            msg.sender,
            amount,
            netAmount,
            DEPOSIT_FEE,
            XP_PER_DEPOSIT,
            xp[msg.sender]
        );
    }

    /**
     * @notice Retire de l'USDC depuis Aave v3 et l'envoie à l'utilisateur (moins 1 USDC de frais)
     * @param amount Montant net que l'utilisateur souhaite recevoir (utiliser type(uint256).max pour tout retirer)
     * @dev Prélève 1 USDC de frais de retrait sur le solde Aave de l'utilisateur
     *      L'utilisateur doit avoir assez pour couvrir le montant + les frais
     *      Attribue XP_PER_DEPOSIT XP à l'utilisateur (comme pour le dépôt)
     *      Suit le pattern CEI : Checks-Effects-Interactions pour la protection contre la réentrance
     */
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (userDeposits[msg.sender] == 0) revert InvalidWithdrawalAmount();

        // Calcule le solde réel de l'utilisateur avec les intérêts
        uint256 userRealBalance = _calculateUserBalance(msg.sender);
        if (userRealBalance == 0) revert InvalidWithdrawalAmount();

        uint256 grossAmount;
        uint256 netAmount;
        uint256 proportionToDeduct;

        if (amount == type(uint256).max) {
            // Retrait maximum possible (tout le solde moins les frais)
            if (userRealBalance <= WITHDRAWAL_FEE)
                revert InsufficientBalanceForWithdrawal();

            grossAmount = userRealBalance;
            netAmount = userRealBalance - WITHDRAWAL_FEE;
            proportionToDeduct = userDeposits[msg.sender];
        } else {
            // Retrait partiel - l'utilisateur spécifie le montant net qu'il souhaite recevoir
            netAmount = amount;
            grossAmount = amount + WITHDRAWAL_FEE;

            // Vérifie que l'utilisateur a assez pour le montant net + les frais
            if (grossAmount > userRealBalance)
                revert InsufficientBalanceForWithdrawal();

            // Calcule la proportion du dépôt initial à déduire
            proportionToDeduct =
                (grossAmount * userDeposits[msg.sender]) /
                userRealBalance;
        }

        if (netAmount == 0) revert InvalidWithdrawalAmount();

        userDeposits[msg.sender] -= proportionToDeduct;
        totalDeposited -= proportionToDeduct;
        totalFeesCollected += WITHDRAWAL_FEE;

        // Attribue l'XP pour le retrait
        xp[msg.sender] += XP_PER_DEPOSIT;
        totalXPDistributed += XP_PER_DEPOSIT;

       
        uint256 actualWithdrawn = aavePool.withdraw(
            address(usdc),
            grossAmount,
            address(this)
        );

        // Transfert le montant net à l'utilisateur (le contrat conserve les frais)
        usdc.safeTransfer(msg.sender, netAmount);

        emit Withdrawal(
            msg.sender,
            actualWithdrawn,
            WITHDRAWAL_FEE,
            netAmount,
            XP_PER_DEPOSIT,
            xp[msg.sender],
            msg.sender
        );
    }

    /**
     * @notice Réclame les récompenses pour un utilisateur et retourne son montant d'XP
     * @param user Adresse de l'utilisateur pour lequel réclamer
     * @return userXP Montant d'XP que l'utilisateur avait avant la réclamation
     * @dev Cette fonction ne peut être appelée que par des contrats autorisés (ex : contrats tokens)
     *      Désactivée par défaut mais peut être activée par le propriétaire
     *      Retourne l'XP de façon atomique avec le marquage comme réclamé pour la sécurité
     */
    function claim(
        address user
    ) external nonReentrant returns (uint256 userXP) {
        if (!claimEnabled) revert ClaimDisabled();
        if (!authorizedClaimers[msg.sender]) revert NotAuthorizedToClaim();
        if (hasClaimed[user]) revert AlreadyClaimed();
        if (xp[user] == 0) revert NoXPToClaim();

        userXP = xp[user];
        hasClaimed[user] = true;

        emit Claimed(user, msg.sender);
    }

    /**
     * @notice Active ou désactive la fonctionnalité de réclamation
     * @param enabled Indique s'il faut activer ou désactiver la réclamation
     * @dev Uniquement appelable par le propriétaire du contrat
     */
    function setClaimEnabled(bool enabled) external onlyOwner {
        claimEnabled = enabled;
        emit ClaimStatusUpdated(enabled);
    }

    /**
     * @notice Met le contrat en pause, empêchant dépôts et retraits
     * @dev Uniquement appelable par le propriétaire du contrat
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Retire la pause du contrat, permettant dépôts et retraits
     * @dev Uniquement appelable par le propriétaire du contrat
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Fonction d'urgence pour retirer tous les frais collectés
     * @param recipient Adresse à laquelle envoyer les frais
     * @dev Uniquement appelable par le propriétaire du contrat
     */
    function emergencyWithdrawFees(address recipient) external onlyOwner {
        require(
            recipient != address(0),
            "ZentixVault: Recipient cannot be zero address"
        );
        uint256 feeBalance = totalFeesCollected;
        require(feeBalance > 0, "ZentixVault: No fees to withdraw");

        totalFeesCollected = 0;
        usdc.safeTransfer(recipient, feeBalance);
    }

    /**
     * @notice Récupère le solde XP d'un utilisateur
     * @param user Adresse à vérifier
     * @return Solde XP de l'utilisateur
     */
    function getXP(address user) external view returns (uint256) {
        return xp[user];
    }

    /**
     * @notice Récupère le solde total aUSDC du contrat
     * @return Solde total aUSDC représentant les fonds investis
     */
    function getTotalInvested() external view returns (uint256) {
        return IERC20(aUSDC).balanceOf(address(this));
    }

    /**
     * @notice Récupère le solde réel de l'utilisateur incluant les intérêts Aave
     * @param user Adresse à vérifier
     * @return Part de l'utilisateur sur le solde total aUSDC (dépôt initial + intérêts)
     * @dev Calcule la part proportionnelle : (userDeposit / totalDeposited) * totalAaveBalance
     */
    function getUserBalance(address user) external view returns (uint256) {
        if (userDeposits[user] == 0 || totalDeposited == 0) {
            return 0;
        }

        uint256 totalAaveBalance = IERC20(aUSDC).balanceOf(address(this));

        // Calcule la part proportionnelle de l'utilisateur
        // userShare = (userDeposit / totalDeposited) * totalAaveBalance
        return (userDeposits[user] * totalAaveBalance) / totalDeposited;
    }

    /**
     * @notice Autorise ou désautorise une adresse à appeler la fonction de réclamation
     * @param claimer Adresse à autoriser/désautoriser (typiquement un contrat token)
     * @param authorized Indique s'il faut autoriser (true) ou désautoriser (false) l'adresse
     * @dev Uniquement appelable par le propriétaire du contrat
     */
    function setClaimerAuthorization(
        address claimer,
        bool authorized
    ) external onlyOwner {
        if (claimer == address(0)) revert InvalidClaimerAddress();

        authorizedClaimers[claimer] = authorized;
        emit ClaimerAuthorizationUpdated(claimer, authorized);
    }

    /**
     * @notice Vérifie si une adresse est autorisée à appeler la fonction de réclamation
     * @param claimer Adresse à vérifier
     * @return Indique si l'adresse est autorisée à réclamer
     */
    function isAuthorizedClaimer(address claimer) external view returns (bool) {
        return authorizedClaimers[claimer];
    }

    /**
     * @notice Fonction interne pour calculer le solde réel de l'utilisateur avec intérêts
     * @param user Adresse à calculer
     * @return Part de l'utilisateur sur le solde total aUSDC
     */
    function _calculateUserBalance(
        address user
    ) internal view returns (uint256) {
        if (userDeposits[user] == 0 || totalDeposited == 0) {
            return 0;
        }

        uint256 totalAaveBalance = IERC20(aUSDC).balanceOf(address(this));
        return (userDeposits[user] * totalAaveBalance) / totalDeposited;
    }
}
