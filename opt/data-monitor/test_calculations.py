#!/usr/bin/env python3
"""
Test date calculations
"""
from datetime import datetime, timedelta

def test_calculate_days(start_date, end_date):
    """Test the fixed calculation"""
    try:
        # Parse start date
        start_day, start_month, start_year = map(int, start_date.split('-'))
        # Parse end date  
        end_day, end_month, end_year = map(int, end_date.split('-'))
        
        start_dt = datetime(start_year, start_month, start_day)
        end_dt = datetime(end_year, end_month, end_day)
        
        # Calculate days (inclusive)
        days = (end_dt - start_dt).days + 1
        
        print(f"Period: {start_date} â†’ {end_date}")
        print(f"Start: {start_dt.strftime('%A, %Y-%m-%d')}")
        print(f"End: {end_dt.strftime('%A, %Y-%m-%d')}")
        print(f"Days (inclusive): {days}")
        print("---")
        
        return days
    except Exception as e:
        print(f"Error: {e}")
        return 0

print("ðŸ§® Testing Date Calculations:")
print("=" * 40)

# Test cases
test_calculate_days("25-08-2025", "11-09-2025")  # Should be 18 days (25 Aug - 11 Sep)
test_calculate_days("12-09-2025", "13-09-2025")  # Should be 2 days (12-13 Sep)
test_calculate_days("01-09-2025", "30-09-2025")  # Should be 30 days (September)

# Verify the specific case
print("ðŸ” Verification for your case:")
print("25 Aug 2025 to 11 Sep 2025:")
start = datetime(2025, 8, 25)  # 25 Aug
end = datetime(2025, 9, 11)    # 11 Sep

# Count days manually
current = start
count = 0
print("Days included:")
while current <= end:
    count += 1
    print(f"{count}. {current.strftime('%d-%m-%Y %A')}")
    current += timedelta(days=1)

print(f"Total: {count} days")
