pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SecureMemeCoin is ERC20, Ownable, ERC20Burnable, ReentrancyGuard, ERC20Permit {
    using SafeMath for uint256;

    uint256 private constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 private constant MAX_WALLET_PERCENTAGE = 5;
    uint256 private constant MAX_TAX_RATE = 10;
    uint256 private constant TRANSFER_COOLDOWN = 30 seconds;

    uint256 private _taxRate;
    address private _taxCollector;
    address private _pendingTaxCollector;
    
    mapping(address => bool) private _excludedFromFees;
    mapping(address => uint256) private _lastTransferTimestamp;
    mapping(address => uint256) private _transferCount;
    mapping(address => bool) private _blacklistedAddresses;

    event TaxRateChanged(address indexed changer, uint256 previousRate, uint256 newRate);
    event TaxCollectorChangeProposed(address indexed currentCollector, address indexed newCollector);
    event TaxCollectorChanged(address indexed previousCollector, address indexed newCollector);
    event AddressBlacklisted(address indexed user, bool status);
    event TransferRejected(address indexed sender, address indexed recipient, string reason);

    constructor() 
        ERC20("SecureMemeCoin", "SMEME") 
        Ownable(msg.sender)
        ERC20Permit("SecureMemeCoin")
    {
        _taxRate = 2;
        _taxCollector = msg.sender;

        _mint(msg.sender, INITIAL_SUPPLY);

        _excludedFromFees[msg.sender] = true;
        _excludedFromFees[address(this)] = true;
    }

    function transfer(address recipient, uint256 amount) 
        public 
        virtual 
        override 
        nonReentrant 
        returns (bool) 
    {
        _securityChecks(_msgSender(), recipient, amount);

        if (!_excludedFromFees[_msgSender()] && !_excludedFromFees[recipient]) {
            uint256 taxAmount = amount.mul(_taxRate).div(100);
            uint256 transferAmount = amount.sub(taxAmount);

            super.transfer(_taxCollector, taxAmount);
            return super.transfer(recipient, transferAmount);
        }

        return super.transfer(recipient, amount);
    }

    function _securityChecks(address sender, address recipient, uint256 amount) internal view {
        require(recipient != address(0), "Transfert vers adresse zero interdit");
        require(amount > 0, "Montant de transfert invalide");
        require(!_blacklistedAddresses[sender], "Adresse bloquee");
        require(!_blacklistedAddresses[recipient], "Adresse destinataire bloquee");
        require(
            balanceOf(recipient).add(amount) <= (totalSupply().mul(MAX_WALLET_PERCENTAGE)).div(100), 
            "Limite de portefeuille depassee"
        );

       
        require(
            block.timestamp >= _lastTransferTimestamp[sender].add(TRANSFER_COOLDOWN),
            "Transferts trop frequents"
        );
    }

    function blacklistAddress(address user, bool status) 
        external 
        onlyOwner 
    {
        _blacklistedAddresses[user] = status;
        emit AddressBlacklisted(user, status);
    }

    function proposeTaxCollector(address newTaxCollector) 
        external 
        onlyOwner 
    {
        require(newTaxCollector != address(0), "Adresse invalide");
        _pendingTaxCollector = newTaxCollector;
        emit TaxCollectorChangeProposed(_taxCollector, newTaxCollector);
    }

   
    function acceptTaxCollector() 
        external 
    {
        require(
            msg.sender == _pendingTaxCollector, 
            "Appel non autorise"
        );
        
        address oldCollector = _taxCollector;
        _taxCollector = _pendingTaxCollector;
        _pendingTaxCollector = address(0);

        _excludedFromFees[oldCollector] = false;
        _excludedFromFees[_taxCollector] = true;

        emit TaxCollectorChanged(oldCollector, _taxCollector);
    }
    function isBlacklisted(address account) public view returns (bool) {
        return _blacklistedAddresses[account];
    }

    function getTaxCollector() public view returns (address) {
        return _taxCollector;
    }

    function burn(uint256 amount) 
        public 
        virtual 
        override 
        nonReentrant 
    {
        require(amount > 0, "Montant de burn invalide");
        super.burn(amount);
    }

    function rescueTokens(IERC20 token, address to) 
        external 
        onlyOwner 
    {
        require(to != address(0), "Adresse de recuperation invalide");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(to, balance);
    }

   
    receive() external payable {
        revert("Transferts directs non autorises");
    }

    fallback() external payable {
        revert("Appels de fonction non reconnus");
    }
}