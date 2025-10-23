# 🌾 Crop Yield Insurance Smart Contract

A decentralized crop insurance system built on Stacks blockchain that provides yield-based insurance coverage for farmers.

## 🚀 Features

- **📋 Policy Creation**: Farmers can create insurance policies for their crops
- **🔮 Oracle Integration**: Trusted oracles report actual crop yields
- **💰 Automated Claims**: Smart contract automatically calculates and processes payouts
- **🛡️ Risk Management**: Premium calculation based on coverage, duration, and expected yield
- **📊 Batch Operations**: Create multiple policies in a single transaction
- **⏸️ Emergency Controls**: Contract owner can pause/resume policies when needed

## 🏗️ Contract Architecture

### Core Functions

#### For Farmers 👨‍🌾

- `create-policy` - Create new insurance policy
- `submit-claim` - Submit claim after harvest period
- `cancel-policy` - Cancel policy within 144 blocks (early cancellation fee applies)
- `get-policy` - View policy details
- `get-farmer-policies` - Get all policies for a farmer

#### For Oracles 🔮

- `submit-yield-report` - Report actual crop yields
- `verify-yield-report` - Verify previously submitted reports

#### For Admin 👑

- `set-oracle-address` - Set primary oracle
- `add-oracle` / `remove-oracle` - Manage oracle whitelist
- `update-policy-parameters` - Update min/max coverage limits
- `emergency-pause` / `resume-policy` - Emergency controls
- `withdraw-excess-funds` - Withdraw surplus funds

## 📖 Usage Guide

### Creating a Policy

```clarity
(contract-call? .Crop-Yield-Insurance create-policy 
  "corn"        ;; crop type
  u50000        ;; expected yield (kg)
  u1000000      ;; coverage amount (micro-STX)
  u1008)        ;; duration in blocks (~1 week)
```

### Premium Calculation 💵

Premiums are calculated using:
- Base rate: 0.5%
- Risk factor: coverage / expected yield
- Time factor: duration / 144 blocks

### Claiming Process 📝

1. **Policy Creation**: Farmer creates policy and pays premium
2. **Growing Period**: Policy remains active during crop growth
3. **Harvest**: Oracle reports actual yield after harvest
4. **Claim Submission**: Farmer submits claim within 1008 blocks (~1 week) after policy end
5. **Payout**: Automatic payout if actual yield < 75% of expected yield

### Payout Formula 📊

- **Trigger**: Actual yield ≤ 75% of expected yield
- **Minimum Loss**: Must have ≥25% yield loss
- **Payout**: (Coverage × Loss Percentage) / 100

## 🔧 Development Setup

### Prerequisites

- [Clarinet](https://docs.hiro.so/stacks/clarinet)
- Node.js (for testing)

### Installation

```bash
git clone <repository-url>
cd Crop-Yield-Insurance
clarinet check
npm install
npm test
```

### Running Tests

```bash
clarinet test
npm test
```

## 🌐 Contract Interface

### Policy Structure

```clarity
{
  farmer: principal,
  crop-type: (string-ascii 50),
  expected-yield: uint,
  coverage-amount: uint,
  premium-amount: uint,
  start-block: uint,
  end-block: uint,
  status: (string-ascii 20),  ;; "active", "reported", "claimed", "cancelled", "paused"
  claim-submitted: bool,
  actual-yield: (optional uint),
  payout-amount: (optional uint)
}
```

### Error Codes

| Code | Description |
|------|-------------|
| 100  | Not authorized |
| 101  | Invalid policy |
| 102  | Policy expired |
| 103  | Policy not active |
| 104  | Insufficient funds |
| 105  | Claim already submitted |
| 106  | Invalid yield data |
| 107  | Policy not found |
| 108  | Invalid parameters |
| 109  | Oracle not set |

## 🔒 Security Features

- **Owner Controls**: Only contract owner can manage oracles and emergency functions
- **Oracle Verification**: Only whitelisted oracles can submit yield reports
- **Time Locks**: Claims must be submitted within specified timeframes
- **Fund Protection**: Reserved funds calculation prevents over-withdrawal

## 📈 Example Scenarios

### Successful Claim 🎯

1. Farmer expects 100kg yield, buys 1000 STX coverage
2. Oracle reports actual yield: 60kg (60% of expected)
3. Loss = 40%, meets 25% minimum threshold
4. Payout = 1000 STX × 40% = 400 STX

### No Payout Scenario ❌

1. Farmer expects 100kg yield, buys 1000 STX coverage  
2. Oracle reports actual yield: 85kg (85% of expected)
3. Loss = 15%, below 25% minimum threshold
4. No payout issued

## 🚨 Important Notes

- Policies can only be cancelled within first 144 blocks (10% fee)
- Claims must be submitted within 1008 blocks after policy expiration
- Minimum premium enforced for risk management
- Oracle reports are required before claims can be processed

## 📞 Support

For questions or support, please open an issue in the repository.

---

*Built with ❤️ on Stacks blockchain*
