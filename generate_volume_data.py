import json
import csv
import time
from collections import defaultdict
from typing import Dict, List, Tuple, Any
from web3 import Web3
from web3.exceptions import BlockNotFound, TransactionNotFound
import requests
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

# Configuration
ALCHEMY_URL = "https://berachain-mainnet.g.alchemy.com/v2/h6emmq6kC1M6yx7CrQEohQNm6svMt6i1"
TOTAL_BERA_TOKENS = 34000

# Pool addresses
POOLS = {
    "YEETARD": "0xe9171252d2EEc5BA1eefB6e2FEf62BC32c061AFA",
    "BULLA_1": "0x9c32e283aad3cB32832096873aa94994B0d9386C",
    "BULLA_2": "0xaAf5DEFf621B743f25356F7692c171dFafaeF9dC",
    "BULLA_3": "0x6DC89967820563cE095696a915237128e146965E",
    "BABY_BERA": "0x304F9c77C303Eb9445f81Ba6De3d0d516372Ea97"
}

# SwapNFTOutPair event signature
SWAP_NFT_OUT_PAIR_TOPIC = Web3.keccak(text="SwapNFTOutPair(uint256,uint256[],uint256)").hex()

# Initialize Web3
w3 = Web3(Web3.HTTPProvider(ALCHEMY_URL))

def get_pool_events(pool_address: str, from_block: int = 0, to_block: int = None) -> List[Dict]:
    """Fetch SwapNFTOutPair events for a specific pool"""
    events = []
    
    if to_block is None:
        to_block = w3.eth.block_number
    
    # Process in chunks to avoid rate limits
    chunk_size = 5000
    current_block = from_block
    
    while current_block <= to_block:
        end_block = min(current_block + chunk_size, to_block)
        
        try:
            filter_params = {
                "fromBlock": hex(current_block),
                "toBlock": hex(end_block),
                "address": pool_address,
                "topics": [SWAP_NFT_OUT_PAIR_TOPIC]
            }
            
            logs = w3.eth.get_logs(filter_params)
            
            for log in logs:
                # Decode the event data
                amount_in = int(log["data"][:66], 16)  # First 32 bytes
                
                # Get transaction details to find the sender
                tx = w3.eth.get_transaction(log["transactionHash"])
                
                events.append({
                    "pool": pool_address,
                    "tx_hash": log["transactionHash"].hex(),
                    "block_number": log["blockNumber"],
                    "address": tx["from"],
                    "amount_in": amount_in,
                    "log_index": log["logIndex"]
                })
            
            print(f"Processed blocks {current_block} to {end_block} for pool {pool_address}")
            current_block = end_block + 1
            time.sleep(0.1)  # Rate limiting
            
        except Exception as e:
            print(f"Error processing blocks {current_block} to {end_block}: {e}")
            time.sleep(1)
            continue
    
    return events

def calculate_volumes(all_events: List[Dict]) -> Dict[str, Dict[str, Any]]:
    """Calculate trading volumes per address and per collection"""
    address_data = defaultdict(lambda: {
        "total_volume": 0,
        "collections": defaultdict(int),
        "tx_count": 0
    })
    
    collection_map = {
        POOLS["YEETARD"]: "YEETARD",
        POOLS["BULLA_1"]: "BULLA",
        POOLS["BULLA_2"]: "BULLA",
        POOLS["BULLA_3"]: "BULLA",
        POOLS["BABY_BERA"]: "BABY_BERA"
    }
    
    for event in all_events:
        address = event["address"].lower()
        pool = event["pool"]
        volume = event["amount_in"] / 1e18  # Convert from wei to BERA
        collection = collection_map[pool]
        
        address_data[address]["total_volume"] += volume
        address_data[address]["collections"][collection] += volume
        address_data[address]["tx_count"] += 1
    
    return dict(address_data)

def distribute_by_collection(address_data: Dict[str, Dict[str, Any]], total_tokens: float) -> Dict[str, float]:
    """Distribute tokens by allocating 1/3 to each collection, then by volume within each"""
    # Group addresses by collection and calculate volumes
    collection_volumes = {
        "YEETARD": {},
        "BULLA": {},
        "BABY_BERA": {}
    }
    
    for address, data in address_data.items():
        for collection, volume in data["collections"].items():
            if volume > 0:
                collection_volumes[collection][address] = volume
    
    # Calculate tokens per collection (1/3 each)
    tokens_per_collection = total_tokens / 3
    
    distribution = defaultdict(float)
    
    # Distribute within each collection based on volume
    for collection, addresses in collection_volumes.items():
        total_collection_volume = sum(addresses.values())
        
        if total_collection_volume > 0:
            for address, volume in addresses.items():
                allocation = (volume / total_collection_volume) * tokens_per_collection
                distribution[address] += allocation
    
    return dict(distribution)

def distribute_by_total_volume(address_data: Dict[str, Dict[str, Any]], total_tokens: float) -> Dict[str, float]:
    """Distribute all tokens based on total trading volume across all pools"""
    total_volume = sum(data["total_volume"] for data in address_data.values())
    
    distribution = {}
    for address, data in address_data.items():
        if total_volume > 0:
            distribution[address] = (data["total_volume"] / total_volume) * total_tokens
        else:
            distribution[address] = 0
    
    return distribution

def main():
    """Main function to orchestrate the airdrop calculation"""
    print("Starting Berachain airdrop calculation...")
    print(f"Total BERA to distribute: {TOTAL_BERA_TOKENS}")
    print(f"Pools to analyze: {len(POOLS)}")
    
    # Fetch all events
    all_events = []
    for pool_name, pool_address in POOLS.items():
        print(f"\nFetching events for {pool_name} pool...")
        events = get_pool_events(pool_address, from_block=0)
        all_events.extend(events)
        print(f"Found {len(events)} events for {pool_name}")
    
    print(f"\nTotal events found: {len(all_events)}")
    
    # Calculate volumes
    print("\nCalculating trading volumes...")
    address_data = calculate_volumes(all_events)
    print(f"Unique addresses found: {len(address_data)}")
    
    # Calculate distributions
    print("\nCalculating token distributions...")
    print("Method 1: By collection (1/3 of 34,000 BERA per collection)")
    collection_distribution = distribute_by_collection(address_data, TOTAL_BERA_TOKENS)
    
    print("Method 2: By total volume (all 34,000 BERA)")
    volume_distribution = distribute_by_total_volume(address_data, TOTAL_BERA_TOKENS)
    
    # Create separate distribution results
    collection_based_results = {}
    volume_based_results = {}
    
    for address in address_data.keys():
        collection_based_results[address] = {
            "allocation": collection_distribution.get(address, 0),
            "address_data": address_data[address]
        }
        volume_based_results[address] = {
            "allocation": volume_distribution.get(address, 0),
            "address_data": address_data[address]
        }
    
    # Sort by allocation for both methods
    sorted_collection = sorted(collection_based_results.items(), 
                             key=lambda x: x[1]["allocation"], reverse=True)
    sorted_volume = sorted(volume_based_results.items(), 
                          key=lambda x: x[1]["allocation"], reverse=True)
    
    # Output results
    print("\n" + "="*80)
    print("AIRDROP DISTRIBUTION RESULTS")
    print("="*80)
    
    print("\nMETHOD 1: BY COLLECTION (1/3 per collection)")
    print(f"{'Address':<45} {'BERA Allocation':<15} {'Volume (BERA)':<15}")
    print("-"*75)
    
    for i, (address, data) in enumerate(sorted_collection[:20]):
        print(f"{address:<45} {data['allocation']:>14.4f} {data['address_data']['total_volume']:>14.4f}")
    
    print("\n\nMETHOD 2: BY TOTAL VOLUME")
    print(f"{'Address':<45} {'BERA Allocation':<15} {'Volume (BERA)':<15}")
    print("-"*75)
    
    for i, (address, data) in enumerate(sorted_volume[:20]):
        print(f"{address:<45} {data['allocation']:>14.4f} {data['address_data']['total_volume']:>14.4f}")
    
    # Calculate collection stats
    collection_stats = {}
    for collection in ["YEETARD", "BULLA", "BABY_BERA"]:
        collection_volume = 0
        collection_traders = 0
        for address, data in address_data.items():
            if collection in data["collections"] and data["collections"][collection] > 0:
                collection_volume += data["collections"][collection]
                collection_traders += 1
        collection_stats[collection] = {
            "total_volume": collection_volume,
            "unique_traders": collection_traders,
            "tokens_allocated": TOTAL_BERA_TOKENS / 3
        }
    
    # Save full results to JSON
    output_data = {
        "summary": {
            "total_bera_distributed": TOTAL_BERA_TOKENS,
            "unique_addresses": len(address_data),
            "total_events": len(all_events),
            "pools_analyzed": list(POOLS.keys()),
            "collection_stats": collection_stats
        },
        "distribution_by_collection": {
            address: {
                "allocation": data["allocation"],
                "total_volume_bera": data["address_data"]["total_volume"],
                "transaction_count": data["address_data"]["tx_count"],
                "collections_traded": dict(data["address_data"]["collections"])
            }
            for address, data in collection_based_results.items()
        },
        "distribution_by_volume": {
            address: {
                "allocation": data["allocation"],
                "total_volume_bera": data["address_data"]["total_volume"],
                "transaction_count": data["address_data"]["tx_count"],
                "collections_traded": dict(data["address_data"]["collections"])
            }
            for address, data in volume_based_results.items()
        }
    }
    
    with open("bera_airdrop_distributions.json", "w") as f:
        json.dump(output_data, f, indent=2)
    
    # Also save CSV files for both distribution methods
    
    # Save collection-based distribution CSV
    with open("bera_airdrop_collection_based.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "amount"])
        for address, data in sorted_collection:
            if data["allocation"] > 0:
                # Convert to wei (18 decimals)
                amount_wei = int(data["allocation"] * 1e18)
                writer.writerow([address, amount_wei])
    
    # Save volume-based distribution CSV
    with open("bera_airdrop_volume_based.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["address", "amount"])
        for address, data in sorted_volume:
            if data["allocation"] > 0:
                # Convert to wei (18 decimals)
                amount_wei = int(data["allocation"] * 1e18)
                writer.writerow([address, amount_wei])
    
    print(f"\n\nFull results saved to:")
    print(f"  - bera_airdrop_distributions.json")
    print(f"  - bera_airdrop_collection_based.csv")
    print(f"  - bera_airdrop_volume_based.csv")
    
    # Print collection statistics
    print("\n\nCOLLECTION STATISTICS:")
    print(f"{'Collection':<15} {'Volume (BERA)':<15} {'Traders':<10} {'BERA Allocated':<15}")
    print("-"*55)
    for collection, stats in collection_stats.items():
        print(f"{collection:<15} {stats['total_volume']:>14.4f} {stats['unique_traders']:>9} {stats['tokens_allocated']:>14.4f}")
    
    # Verify distributions
    total_collection_dist = sum(data["allocation"] for data in collection_based_results.values())
    total_volume_dist = sum(data["allocation"] for data in volume_based_results.values())
    print(f"\nVerification:")
    print(f"Collection-based distribution total: {total_collection_dist:.4f} BERA")
    print(f"Volume-based distribution total: {total_volume_dist:.4f} BERA")
    
    # Create visualizations
    create_distribution_charts(sorted_collection, sorted_volume)

def create_distribution_charts(sorted_collection: List[Tuple[str, Dict]], 
                             sorted_volume: List[Tuple[str, Dict]]):
    """Create pie charts for top addresses in each distribution method"""
    
    # Set up the figure with two subplots
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
    fig.suptitle('BERA Token Distribution Analysis', fontsize=16, fontweight='bold')
    
    # Number of top addresses to show
    TOP_N = 15
    
    # Process collection-based distribution
    collection_data = []
    collection_labels = []
    collection_total = 0
    
    for i, (address, data) in enumerate(sorted_collection):
        if i < TOP_N and data["allocation"] > 0:
            collection_data.append(data["allocation"])
            collection_labels.append(f"{address[:6]}...{address[-4:]}: {data['allocation']:.2f}")
            collection_total += data["allocation"]
        elif data["allocation"] > 0:
            collection_total += data["allocation"]
    
    # Add "Others" category if there are more addresses
    others_collection = 34000 - collection_total
    if others_collection > 0 and len(sorted_collection) > TOP_N:
        collection_data.append(others_collection)
        collection_labels.append(f"Others ({len(sorted_collection) - TOP_N} addresses): {others_collection:.2f}")
    
    # Process volume-based distribution
    volume_data = []
    volume_labels = []
    volume_total = 0
    
    for i, (address, data) in enumerate(sorted_volume):
        if i < TOP_N and data["allocation"] > 0:
            volume_data.append(data["allocation"])
            volume_labels.append(f"{address[:6]}...{address[-4:]}: {data['allocation']:.2f}")
            volume_total += data["allocation"]
        elif data["allocation"] > 0:
            volume_total += data["allocation"]
    
    # Add "Others" category if there are more addresses
    others_volume = 34000 - volume_total
    if others_volume > 0 and len(sorted_volume) > TOP_N:
        volume_data.append(others_volume)
        volume_labels.append(f"Others ({len(sorted_volume) - TOP_N} addresses): {others_volume:.2f}")
    
    # Create color palette
    if len(collection_data) > 1:
        colors = plt.cm.Set3([i/float(len(collection_data)-1) for i in range(len(collection_data))])
    else:
        colors = ['#1f77b4']
    
    # Create pie chart for collection-based distribution
    ax1.pie(collection_data, labels=collection_labels, autopct='%1.1f%%', 
            colors=colors, startangle=90, textprops={'fontsize': 9})
    ax1.set_title('Collection-Based Distribution\n(1/3 per collection)', fontsize=14, pad=20)
    
    # Create pie chart for volume-based distribution
    if len(volume_data) > 1:
        colors2 = plt.cm.Set3([i/float(len(volume_data)-1) for i in range(len(volume_data))])
    else:
        colors2 = ['#1f77b4']
    ax2.pie(volume_data, labels=volume_labels, autopct='%1.1f%%', 
            colors=colors2, startangle=90, textprops={'fontsize': 9})
    ax2.set_title('Volume-Based Distribution\n(Pro-rata by total volume)', fontsize=14, pad=20)
    
    # Adjust layout and save
    plt.tight_layout()
    plt.savefig('bera_distribution_charts.png', dpi=300, bbox_inches='tight')
    print(f"\nVisualization saved to bera_distribution_charts.png")
    
    # Create individual detailed charts for each distribution
    create_detailed_chart(sorted_collection, "Collection-Based Distribution", 
                         "bera_collection_distribution_detailed.png")
    create_detailed_chart(sorted_volume, "Volume-Based Distribution", 
                         "bera_volume_distribution_detailed.png")

def create_detailed_chart(sorted_data: List[Tuple[str, Dict]], title: str, filename: str):
    """Create a detailed bar chart for a distribution method"""
    
    TOP_N = 20
    
    # Prepare data
    addresses = []
    allocations = []
    
    for i, (address, data) in enumerate(sorted_data[:TOP_N]):
        if data["allocation"] > 0:
            addresses.append(f"{address[:6]}...{address[-4:]}")
            allocations.append(data["allocation"])
    
    # Create figure
    fig, ax = plt.subplots(figsize=(12, 8))
    
    # Create horizontal bar chart
    if len(addresses) > 1:
        bar_colors = plt.cm.viridis([i/float(len(addresses)-1) for i in range(len(addresses))])
    else:
        bar_colors = ['#1f77b4']
    bars = ax.barh(addresses, allocations, color=bar_colors)
    
    # Add value labels on bars
    for i, (bar, value) in enumerate(zip(bars, allocations)):
        ax.text(bar.get_width() + 20, bar.get_y() + bar.get_height()/2, 
                f'{value:.2f} BERA', va='center', fontsize=10)
    
    # Customize chart
    ax.set_xlabel('BERA Tokens Allocated', fontsize=12)
    ax.set_ylabel('Addresses', fontsize=12)
    ax.set_title(f'{title} - Top {len(addresses)} Recipients', fontsize=14, fontweight='bold', pad=20)
    ax.grid(axis='x', alpha=0.3)
    
    # Add total information
    total_shown = sum(allocations)
    ax.text(0.02, 0.98, f'Total shown: {total_shown:.2f} BERA ({total_shown/340:.1f}%)', 
            transform=ax.transAxes, fontsize=10, verticalalignment='top',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    plt.tight_layout()
    plt.savefig(filename, dpi=300, bbox_inches='tight')
    print(f"Detailed chart saved to {filename}")

if __name__ == "__main__":
    main()