#!/bin/bash

# Usage: dict-lookup [en|fr]
# Default is English if no argument

# Get current keyboard layout
current_layout=$(setxkbmap -query | grep layout | awk '{print $2}')

# Determine language based on layout or argument
if [ -n "$1" ]; then
    # Argument takes priority if passed
    LANG="$1"
elif [ "$current_layout" = "ca" ] || [ "$current_layout" = "ca_multi" ]; then
    LANG="fr"
else
    LANG="en"
fi

# Get highlighted text
word=$(xclip -o -selection primary 2>/dev/null)

# Clean and lowercase
word=$(echo "$word" | tr -d '\n' | xargs | cut -d' ' -f1)
word="${word,,}"  # Convert to lowercase - bash 4+

if [ -z "$word" ]; then
    word=$(xclip -o -selection clipboard 2>/dev/null)
fi

fetch-usito() {
  # Usito
  URL="https://usito.usherbrooke.ca/d%C3%A9finitions/${1}"
  local html=$(curl -s "$URL")

  # DEFINITIONS=$(echo "$html" | htmlq '.def_sous_entree-style' --text 2>/dev/null | head -3 | nl -w1 -s'. ' | sed 'G')
  DEFINITIONS=""
  local count=0

  for i in 1 2 3; do
    def=$(echo "$html" | htmlq ".sens-styleB:nth-of-type($i) .def_sous_entree-style" --text 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | grep -o '^[^.]*\.')
    if [ -n "$def" ]; then
        count=$((count + 1))
        DEFINITIONS+="$count. $def"$'\n\n'
    fi
  done

  count=0
  if [ -z "$DEFINITIONS" ]; then
    for i in 1 2 3; do
      def=$(echo "$html" | htmlq ".sens-styleC:nth-of-type($i) .def_sous_entree-style" --text 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | grep -o '^[^.]*\.')
      if [ -n "$def" ]; then
        count=$((count + 1))
        DEFINITIONS+="$count. $def"$'\n\n'
      fi
    done
  fi
}

# Query based on language
if [ "$LANG" = "fr" ]; then
  if [ -z "$word" ]; then
    notify-send "Recherche Dictionnaire" "Pas de texte sélectioné" -i None
    exit 1
  fi

  # fetch usito API to get first available url param (stripped of '.ad')
  params=$(curl -G "https://usito.usherbrooke.ca/v2/documents?" \
    --data-urlencode "contient=$word" \
    | jq -r '.["données"].items[0].["clé"].id')

  fetch-usito "${params//.ad/}"


  if [ -z "$DEFINITIONS" ]; then
      notify-send "Usito: $word" "Aucune définition trouvée" -i None
      exit 0
  fi
  notify-send " $word" "${DEFINITIONS}Voir plus: $URL" -t 15000 -i None
else
  if [ -z "$word" ]; then
    notify-send "Dictionary Lookup" "No text selected" -i None
    exit 1
  fi

  # Query the Free Dictionary API
  response=$(curl -s "https://api.dictionaryapi.dev/api/v2/entries/en/$word")

  # Check if the API returned an error
  if echo "$response" | grep -q '"title":"No Definitions Found"'; then
    notify-send "DictionaryAPI: $word" "No definition found" -i None
    exit 0
  fi

  # Parse based on whether jq is available
  if command -v jq &> /dev/null; then
    # Better parsing with jq - get multiple definitions
    part_of_speech=$(echo "$response" | jq -r '.[0].meanings[0].partOfSpeech // empty')

    # Get up to 3 definitions
    definitions=$(echo "$response" | jq -r '.[0].meanings[0].definitions[0:3] | to_entries | map("" + (.key + 1 | tostring) + ". " + .value.definition) | join("\n\n")' 2>/dev/null)

    # Fallback if jq parsing fails
    if [ -z "$definitions" ]; then
      definitions=$(echo "$response" | jq -r '.[0].meanings[0].definitions[0].definition // "Could not parse definition"')
    fi
  else
    # Fallback to grep/sed parsing
    part_of_speech=$(echo "$response" | grep -o '"partOfSpeech":"[^"]*"' | head -1 | sed 's/"partOfSpeech":"//;s/"$//')
    definitions=$(echo "$response" | grep -o '"definition":"[^"]*"' | head -1 | sed 's/"definition":"//;s/"$//')
  fi

  # Check if we got a definition
  if [ -z "$definitions" ]; then
    notify-send "Dictionary: $word" "Could not parse definition" -i None
    exit 1
  fi

  # Format and display the notification
  if [ -n "$part_of_speech" ]; then
    notify-send " $word ($part_of_speech)" "$definitions" -t 15000 -i None
  else
    notify-send " $word" "$definitions" -t 15000 -i None
  fi
fi
