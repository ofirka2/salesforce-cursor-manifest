#!/bin/bash

# Salesforce Org Phased Retrieval Script
# Designed to be executed by Cursor Agent

set -e  # Exit on error

MANIFEST_DIR="manifest"
FORCE_APP_DIR="force-app"
REPORTS_DIR="reports"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create necessary directories
mkdir -p "$REPORTS_DIR"

# Function to retrieve metadata
retrieve_phase() {
    local phase_num=$1
    local phase_name=$2
    local manifest_file=$3
    local target_dir="${FORCE_APP_DIR}/${phase_num}-${phase_name}"
    
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${YELLOW}Phase ${phase_num}: ${phase_name}${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    # Run retrieval
    echo "Retrieving metadata..."
    if sf project retrieve start \
        --manifest "${MANIFEST_DIR}/${manifest_file}.package.xml" \
        --target-metadata-dir "$target_dir" \
        --wait 30 2>&1 | tee /tmp/sf-retrieve-output.log; then
        
        echo -e "${GREEN}✅ Phase ${phase_num} completed successfully${NC}"
        
        # Generate summary
        generate_summary "$phase_num" "$phase_name" "$target_dir"
        
        return 0
    else
        echo -e "${RED}⚠️  Phase ${phase_num} failed, retrying with longer timeout...${NC}"
        
        # Retry with longer timeout
        if sf project retrieve start \
            --manifest "${MANIFEST_DIR}/${manifest_file}.package.xml" \
            --target-metadata-dir "$target_dir" \
            --wait 60 2>&1 | tee /tmp/sf-retrieve-output.log; then
            
            echo -e "${GREEN}✅ Phase ${phase_num} completed on retry${NC}"
            generate_summary "$phase_num" "$phase_name" "$target_dir"
            return 0
        else
            echo -e "${RED}❌ Phase ${phase_num} failed after retry${NC}"
            echo "[$(date)] Phase ${phase_num}: ${phase_name} failed" >> "${REPORTS_DIR}/errors.log"
            
            # Generate failure summary
            {
                echo "# Phase ${phase_num}: ${phase_name} - FAILED"
                echo ""
                echo "**Date**: $(date)"
                echo ""
                echo "## Error"
                echo "Retrieval failed after retry. Check errors.log for details."
                echo ""
            } > "${REPORTS_DIR}/phase-${phase_num}-summary.md"
            
            return 1
        fi
    fi
}

# Function to generate summary
generate_summary() {
    local phase_num=$1
    local phase_name=$2
    local target_dir=$3
    local summary_file="${REPORTS_DIR}/phase-${phase_num}-summary.md"
    
    echo "Generating summary..."
    
    {
        echo "# Phase ${phase_num}: ${phase_name}"
        echo ""
        echo "**Retrieval Date**: $(date)"
        echo "**Status**: ✅ Success"
        echo ""
        echo "## Metadata Counts"
        echo ""
        
        # Count files by extension/type
        if [ -d "$target_dir" ]; then
            echo "**Total metadata files**: $(find "$target_dir" -type f | wc -l | xargs)"
            echo ""
            
            # Count by subdirectory
            echo "### By Type"
            echo ""
            for dir in "$target_dir"/*/ ; do
                if [ -d "$dir" ]; then
                    local dirname=$(basename "$dir")
                    local count=$(find "$dir" -type f | wc -l | xargs)
                    echo "- **${dirname}**: ${count} files"
                fi
            done
            echo ""
            
            echo "## Directory Structure"
            echo '```'
            if command -v tree &> /dev/null; then
                tree -L 3 "$target_dir"
            else
                find "$target_dir" -type d | head -20
            fi
            echo '```'
            echo ""
            
            # Phase-specific analysis
            case $phase_num in
                1)
                    echo "## Key Objects"
                    if [ -d "$target_dir/objects" ]; then
                        echo '```'
                        ls "$target_dir/objects" | head -20
                        echo '```'
                    fi
                    ;;
                2)
                    echo "## Automation Summary"
                    [ -d "$target_dir/classes" ] && echo "- Apex Classes: $(ls "$target_dir/classes"/*.cls 2>/dev/null | wc -l | xargs)"
                    [ -d "$target_dir/triggers" ] && echo "- Apex Triggers: $(ls "$target_dir/triggers"/*.trigger 2>/dev/null | wc -l | xargs)"
                    [ -d "$target_dir/flows" ] && echo "- Flows: $(ls "$target_dir/flows"/*.flow-meta.xml 2>/dev/null | wc -l | xargs)"
                    ;;
                3)
                    echo "## UI Components Summary"
                    [ -d "$target_dir/lwc" ] && echo "- Lightning Web Components: $(ls -d "$target_dir/lwc"/*/ 2>/dev/null | wc -l | xargs)"
                    [ -d "$target_dir/aura" ] && echo "- Aura Components: $(ls -d "$target_dir/aura"/*/ 2>/dev/null | wc -l | xargs)"
                    [ -d "$target_dir/pages" ] && echo "- Visualforce Pages: $(ls "$target_dir/pages"/*.page 2>/dev/null | wc -l | xargs)"
                    ;;
                4)
                    echo "## Integration Points"
                    if [ -d "$target_dir/namedCredentials" ]; then
                        echo "### Named Credentials"
                        echo '```'
                        ls "$target_dir/namedCredentials" 2>/dev/null || echo "None found"
                        echo '```'
                    fi
                    if [ -d "$target_dir/remoteSiteSettings" ]; then
                        echo "### Remote Site Settings"
                        echo '```'
                        ls "$target_dir/remoteSiteSettings" 2>/dev/null || echo "None found"
                        echo '```'
                    fi
                    ;;
            esac
        else
            echo "⚠️  Target directory not found: $target_dir"
        fi
        
    } > "$summary_file"
    
    echo -e "${GREEN}Summary created: $summary_file${NC}"
}

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "  Salesforce Org Phased Retrieval"
    echo "========================================="
    echo ""
    echo "Start time: $(date)"
    echo ""
    
    # Track start time
    START_TIME=$(date +%s)
    
    # Track success/failure
    TOTAL_PHASES=6
    SUCCESSFUL_PHASES=0
    FAILED_PHASES=0
    
    # Execute phases (6 phases total)
    retrieve_phase "1" "foundation" "org-metadata-inventory" && ((SUCCESSFUL_PHASES++)) || ((FAILED_PHASES++))
    retrieve_phase "2" "automation" "automation-layer" && ((SUCCESSFUL_PHASES++)) || ((FAILED_PHASES++))
    retrieve_phase "3" "ui" "ui-components" && ((SUCCESSFUL_PHASES++)) || ((FAILED_PHASES++))
    retrieve_phase "4" "integration" "integration-security" && ((SUCCESSFUL_PHASES++)) || ((FAILED_PHASES++))
    retrieve_phase "5" "communication" "email-templates-documents" && ((SUCCESSFUL_PHASES++)) || ((FAILED_PHASES++))
    retrieve_phase "6" "testing" "test-quality" && ((SUCCESSFUL_PHASES++)) || ((FAILED_PHASES++))
    
    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    
    # Final summary
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}   Retrieval Complete!${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "End time: $(date)"
    echo "Duration: ${MINUTES}m ${SECONDS}s"
    echo ""
    echo -e "${GREEN}Successful phases: ${SUCCESSFUL_PHASES}/${TOTAL_PHASES}${NC}"
    [ $FAILED_PHASES -gt 0 ] && echo -e "${RED}Failed phases: ${FAILED_PHASES}/${TOTAL_PHASES}${NC}"
}

# Run main function
main "$@"
