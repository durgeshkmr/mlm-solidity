pragma solidity ^0.4.24;

//import "./EthPriceDependent.sol";
import "./EthPriceDependentTest.sol";
import "./SigFredToken.sol";
import "./ownership/Ownable.sol";
import "./lifecycle/Destructible.sol";
import "./math/SafeMath.sol";
import "./math/Math.sol";


contract SigFred is Ownable, Destructible, EthPriceDependentTest, SigFredToken {
    using SafeMath for uint256;

    // Contract Events
    event InvestorCreated(address investorAddr);
    event InvestorLevelUpd(address investorAddr, uint8 new_level);
    event InvestorPayOut(address investorAddr, uint amount);
    event InvestorPackBought(address investorAddr, string packName, uint amountEUR);
    event InvestorRewardUpd(address investorAddr, uint8 iteration, uint amountEUR, uint amountETH);

    event TokensBuy(address investorAddr, uint amountTokens, uint amountInETH);
    event TokensSell(address investorAddr, uint amountTokens, uint amountInETH);

    event TokensPercentsPayOut(address investorAddr, uint amountTokens, uint amountInETH);
    event TokensPercentsReinvest(address investorAddr, uint amountTokens);

    event TokensReferralReward(address investorAddr, address fromInvestorAddr, uint amountTokens);

    // Available Packs and prices for Investors
    mapping (bytes16 => uint32) public PackPrices;

    // Investor Rewarding array
    uint8[][] public Rewards = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 10, 1, 1, 1, 1, 1, 1],
    [0, 10, 2, 2, 2, 2, 2, 2],
    [0, 10, 3, 3, 3, 3, 3, 3],
    [0, 10, 4, 4, 4, 4, 4, 4],
    [0, 10, 5, 5, 5, 5, 5, 5]
    ];

    // Investors struct
    struct Investor {
        bool is_exists; // Flag is investor exists
        address inviter; // Address of investor who invited this investor
        uint8 level; // Current level of this investor (can be 1-6 regarding rewards table)
        uint32 invested_eur; // Current investments of this investor
        uint64 invested_by_invited_eur; // Current investments amount of invited people
        uint referral_reward_eur; // Current amount of rewarding for invited people in EUR
        uint referral_reward_eth; // Current amount of rewarding for invited people in ETH
        uint referral_reward_payed_eth; // Current amount of payed rewardings
        bool silver_bought; // Is investor bought Silver Pack
        bool gold_bought; // Is investor bought Gold Pack
        bool platinum_bought; // Is investor bought Platinum Pack
        // Saver PART
        uint saver_block_lock;
        uint saver_referral_reward_tokens;
    }

    // Investors
    mapping (address => Investor) private investors;

    // Constructor
    constructor() public payable {
        setPacksPrices(100, 300, 1000);
    }

    // Set Pack Prices in EUR
    function setPacksPrices(uint32 _silverPackPrice, uint32 _goldPackPrice, uint32 _platinumPackPrice) public onlyOwner {
        PackPrices['Silver'] = _silverPackPrice;
        PackPrices['Gold'] = _goldPackPrice;
        PackPrices['Platinum'] = _platinumPackPrice;
    }

    // Get Ether Price in EUR cents from Oraclize
    function getEtherPriceInEurCents() public view returns(uint) {
        require( !priceExpired() );
        return m_ETHPriceInCents;
    }

    function createRootInvestor(address _investorAddr, string _referralCode) public returns(bool) {
        require(_investorAddr != address(0));
        require(investors[_investorAddr].is_exists == false);
        require(bytes(_referralCode).length == 7);

        investors[_investorAddr].is_exists = true;

        emit InvestorCreated(_investorAddr);
        return true;
    }

    function createInvestor(address _inviterAddr) public returns(bool) {
        require(_inviterAddr != address(0));
        require(investors[msg.sender].is_exists == false);
        require(investors[_inviterAddr].is_exists == true);

        investors[msg.sender].is_exists = true;
        investors[msg.sender].inviter = _inviterAddr;

        emit InvestorCreated(msg.sender);
        return true;
    }

    function buySilverPack() public payable  {
        require(investors[msg.sender].is_exists == true);
        require(investors[msg.sender].silver_bought == false);
        require((msg.value.mul(getEtherPriceInEurCents())).div(1 ether) >= PackPrices['Silver']*100);

        investors[msg.sender].silver_bought = true;
        investors[msg.sender].invested_eur += PackPrices['Silver'];
        // emit event
        emit InvestorPackBought(msg.sender, 'Silver', PackPrices['Silver']);
        // Recount Level of current investor
        recountInvestorLevel(msg.sender);

        updateParentInvestor(investors[msg.sender].inviter, msg.sender, PackPrices['Silver'], 1);
    }

    function buyGoldPack() public payable {
        require(investors[msg.sender].is_exists == true);
        require(investors[msg.sender].gold_bought == false);
        require((msg.value.mul(getEtherPriceInEurCents())).div(1 ether) >= PackPrices['Gold']*100);

        investors[msg.sender].gold_bought = true;
        investors[msg.sender].invested_eur += PackPrices['Gold'];
        // emit event
        emit InvestorPackBought(msg.sender, 'Gold', PackPrices['Gold']);
        // Recount Level of current investor
        recountInvestorLevel(msg.sender);

        updateParentInvestor(investors[msg.sender].inviter, msg.sender, PackPrices['Gold'], 1);
    }

    function buyPlatinumPack() public payable {
        require(investors[msg.sender].is_exists == true);
        require(investors[msg.sender].platinum_bought == false);
        require((msg.value.mul(getEtherPriceInEurCents())).div(1 ether) >= PackPrices['Platinum']*100);

        investors[msg.sender].platinum_bought = true;
        investors[msg.sender].invested_eur += PackPrices['Platinum'];
        // emit event
        emit InvestorPackBought(msg.sender, 'Platinum', PackPrices['Platinum']);
        // Recount Level of current investor
        recountInvestorLevel(msg.sender);

        updateParentInvestor(investors[msg.sender].inviter, msg.sender, PackPrices['Platinum'], 1);
    }

    function updateParentInvestor(address _investorAddr, address _fromInvestorAddr, uint32 _investmentAmountEUR, uint8 _iteration) private {
        if (_investorAddr != address(0)) {

            if (_iteration == 1) {
                investors[_investorAddr].invested_by_invited_eur += _investmentAmountEUR;
                // Recount Level of current investor
                recountInvestorLevel(_investorAddr);
            }

            // Rewarding Investor according Level and Depth (Index)
            uint8 percentToAdd = Rewards[investors[_investorAddr].level][_iteration];
            if (percentToAdd != 0) {
                uint referral_reward_eur = SafeMath.div(SafeMath.mul(_investmentAmountEUR, percentToAdd), 100);
                uint referral_reward_eth = SafeMath.div(SafeMath.mul(msg.value, percentToAdd), 100);
                investors[_investorAddr].referral_reward_eur += referral_reward_eur;
                investors[_investorAddr].referral_reward_eth += referral_reward_eth;
                emit InvestorRewardUpd(_investorAddr, _iteration, referral_reward_eur, referral_reward_eth);
            }

            _iteration += 1;
            if (_iteration < 8) {
                updateParentInvestor(investors[_investorAddr].inviter, _fromInvestorAddr, _investmentAmountEUR, _iteration);
            }
        }

    }

    // Recount investor's level
    function recountInvestorLevel(address _investorAddr) private returns(bool) {
        uint current_invested_eur = investors[_investorAddr].invested_eur;
        uint current_invested_by_invited_eur = investors[_investorAddr].invested_by_invited_eur;
        uint8 current_level = investors[_investorAddr].level;

        if ( (current_invested_eur >= 1100 ) && (current_invested_by_invited_eur >= 5000 ) ) {
            investors[_investorAddr].level = 5;
        } else if ( (current_invested_eur >= 1000 ) && (current_invested_by_invited_eur >= 2500 ) ) {
            investors[_investorAddr].level = 4;
        } else if ( (current_invested_eur >= 400 ) && (current_invested_by_invited_eur >= 900 ) ) {
            investors[_investorAddr].level = 3;
        } else if ( (current_invested_eur >= 300 ) && (current_invested_by_invited_eur >= 300 ) ) {
            investors[_investorAddr].level = 2;
        } else if ( (current_invested_eur >= 100 ) && (current_invested_by_invited_eur >= 100 ) ) {
            investors[_investorAddr].level = 1;
        }

        if (current_level != investors[_investorAddr].level) {
            emit InvestorLevelUpd(_investorAddr, investors[_investorAddr].level);
        }

        return true;
    }

    // Transfer ETH to any wallet onlyOwner
    function transferETH(address _toAddr, uint _amount) public onlyOwner {
        require(_toAddr != address(0));
        require(_amount > 0);

        _toAddr.transfer(_amount);
    }

    // Investor's payOut function
    function payOut(uint _amount) public {
        require(investors[msg.sender].referral_reward_eth >= _amount);

        investors[msg.sender].referral_reward_eth -= _amount;
        // Save payed rewardings
        investors[msg.sender].referral_reward_payed_eth += _amount;

        msg.sender.transfer(_amount);
        emit InvestorPayOut(msg.sender, _amount);
    }


    // Methods for checking investors Packs bought or not
    function isSilverPackBought() public view returns(bool) {
        return investors[msg.sender].silver_bought;
    }
    function isGoldPackBought() public view returns(bool) {
        return investors[msg.sender].gold_bought;
    }
    function isPlatinumPackBought() public view returns(bool) {
        return investors[msg.sender].platinum_bought;
    }

    // Method for checking investor unpaid Reward amount
    function getUnpaidRewardETH() public view returns(uint) {
        return investors[msg.sender].referral_reward_eth;
    }

    // Method for checking investor paid Reward amount
    function getPaidRewardETH() public view returns(uint) {
        return investors[msg.sender].referral_reward_payed_eth;
    }

    // Method for checking investor Level
    function getLevel() public view returns(uint) {
        return investors[msg.sender].level;
    }

    // Method for checking amount of Investments of invited users
    function getInvestedByInvitedEUR() public view returns(uint) {
        return investors[msg.sender].invested_by_invited_eur;
    }

    // SAVER PART

    function buyTokens() public payable {
        internalBuy(msg.sender, msg.value);
    }

    function sellTokens(uint _tokens) public {
        internalSell(msg.sender, _tokens);
    }

    function internalBuy(address _investor, uint _payment) internal {
        require(_investor != owner());
        require(investors[_investor].is_exists == true);
        require(!priceExpired());
        require((_payment.mul(m_ETHPriceInCents)).div(1 ether) >= c_MinInvestmentInCents);

        // Reinvest token percents
        if (getCurrentTokenPercentsAndReferral() > 0) {
            reinvestCurrentTokenPercents();
        }

        uint tokens = ether2tokens(_payment);

        // change investment stats
        m_currentTokensSold = m_currentTokensSold.add(tokens);

        // send bought tokens to the investor
        _transfer(owner(), _investor, tokens);

        emit TokensBuy(_investor, tokens, _payment);

        // Add one time referral reward to inviter
        if (investors[_investor].inviter != address(0)) {
            address inviter = investors[_investor].inviter;
            uint256 referralTokensReward = tokens.mul(c_tokenOneTimeReferralReward).div(100);
            investors[inviter].saver_referral_reward_tokens = investors[inviter].saver_referral_reward_tokens.add(referralTokensReward);
            emit TokensReferralReward(inviter, _investor, referralTokensReward);
        }
    }

    function internalSell(address _investor, uint _tokens) internal {
        require(_investor != owner());
        require(investors[_investor].is_exists == true);
        require(!priceExpired());
        require(_tokens.mul(c_tokenPayOutPriceInCentsDecimals).div(10) >= c_MinPayOutInCents);
        require(balanceOf(_investor) >= _tokens);

        // Reinvest token percents
        if (getCurrentTokenPercentsAndReferral() > 0) {
            reinvestCurrentTokenPercents();
        }

        // change investment stats
        m_currentTokensSold = m_currentTokensSold.sub(_tokens);

        uint amountInETH = tokens2ether(_tokens);
        _transfer(_investor, owner(), _tokens);

        _investor.transfer(amountInETH);

        emit TokensSell(_investor, _tokens, amountInETH);
    }

    function getCurrentTokenPercentsAndReferral() public view returns(uint) {
        require(investors[msg.sender].is_exists == true);

        uint current_token_percents;

        uint saver_referral_reward_tokens = investors[msg.sender].saver_referral_reward_tokens;

        if (investors[msg.sender].saver_block_lock > 0) {
            current_token_percents = balanceOf(msg.sender).mul(c_tokenDayPercentThousands).div(1000).div(100).mul(block.number-investors[msg.sender].saver_block_lock).div(5900);
        } else {
            current_token_percents = 0;
        }

        return saver_referral_reward_tokens.add(current_token_percents);
    }

    function payOutCurrentTokenPercents() public {
        require(msg.sender != owner());

        uint depositTokenPercents = getCurrentTokenPercentsAndReferral();

        require(depositTokenPercents > 0);

        // Reset referral reward tokens
        investors[msg.sender].saver_referral_reward_tokens = 0;

        uint amountInETH = tokens2ether(depositTokenPercents);
        msg.sender.transfer(amountInETH);

        // save block lock
        investors[msg.sender].saver_block_lock = block.number;

        emit TokensPercentsPayOut(msg.sender,  depositTokenPercents, amountInETH);

    }

    function reinvestCurrentTokenPercents() public {
        require(msg.sender != owner());

        uint depositTokenPercents = getCurrentTokenPercentsAndReferral();

        require(depositTokenPercents > 0);

        // Reset referral reward tokens
        investors[msg.sender].saver_referral_reward_tokens = 0;

        // send percent tokens to the investor
        _transfer(owner(), msg.sender, depositTokenPercents);

        // save block lock
        investors[msg.sender].saver_block_lock = block.number;

        emit TokensPercentsReinvest(msg.sender, depositTokenPercents);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transfer( owner(), newOwner, balanceOf(owner()) );
        _transferOwnership(newOwner);
    }

}