Set-StrictMode -Version Latest

function ConvertTo-Gate14ReMEStrictUtcInstantCoreV1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$Formats
    )

    $originalText = if ($null -eq $Value) { $null } else { [string]$Value }
    $result = [ordered]@{
        originalText = $originalText
        parsed = $false
        uniqueParse = $false
        successfulFormatCount = 0
        matchedFormat = $null
        normalizedUtc = $null
        utcTicks = $null
        sourceOffset = $null
        failureCode = $null
    }

    if ($null -eq $Value) {
        $result.failureCode = 'MISSING_VALUE'
        return [pscustomobject]$result
    }
    if ($Value -isnot [string]) {
        $result.failureCode = 'NON_STRING_VALUE'
        return [pscustomobject]$result
    }
    if ($Value.Length -eq 0) {
        $result.failureCode = 'EMPTY_VALUE'
        return [pscustomobject]$result
    }

    $strictShape = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$'
    if (-not [regex]::IsMatch($Value, $strictShape, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        $result.failureCode = 'NOT_STRICT_ISO8601_OFFSET_TIMESTAMP'
        return [pscustomobject]$result
    }

    $successes = [System.Collections.Generic.List[object]]::new()
    foreach ($format in $Formats) {
        $parsedValue = [DateTimeOffset]::MinValue
        $succeeded = [DateTimeOffset]::TryParseExact(
            $Value,
            $format,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsedValue)
        if ($succeeded) {
            $successes.Add([pscustomobject][ordered]@{
                format = $format
                value = $parsedValue
            })
        }
    }

    $result.successfulFormatCount = $successes.Count
    if ($successes.Count -eq 0) {
        $result.failureCode = 'STRICT_PARSE_FAILED'
        return [pscustomobject]$result
    }
    if ($successes.Count -ne 1) {
        $result.failureCode = 'NON_UNIQUE_PARSE'
        return [pscustomobject]$result
    }

    $selected = $successes[0]
    $result.parsed = $true
    $result.uniqueParse = $true
    $result.matchedFormat = [string]$selected.format
    $result.normalizedUtc = $selected.value.UtcDateTime.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    $result.utcTicks = [int64]$selected.value.UtcDateTime.Ticks
    $result.sourceOffset = $selected.value.Offset.ToString('c', [System.Globalization.CultureInfo]::InvariantCulture)
    return [pscustomobject]$result
}

function ConvertTo-Gate14ReMEStrictUtcInstantV1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )

    $formats = [string[]]@(
        "yyyy-MM-dd'T'HH:mm:ssK",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK"
    )
    return ConvertTo-Gate14ReMEStrictUtcInstantCoreV1 -Value $Value -Formats $formats
}

function Compare-Gate14ReMETrustedTimestampV1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$TrustedText,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$ObservedText
    )

    $trusted = ConvertTo-Gate14ReMEStrictUtcInstantV1 -Value $TrustedText
    $observed = ConvertTo-Gate14ReMEStrictUtcInstantV1 -Value $ObservedText
    $bothParsedUniquely = [bool]($trusted.parsed -and $trusted.uniqueParse -and $observed.parsed -and $observed.uniqueParse)
    $sameUtcInstant = [bool]($bothParsedUniquely -and ([int64]$trusted.utcTicks -eq [int64]$observed.utcTicks))
    $accepted = [bool]($bothParsedUniquely -and $sameUtcInstant)

    $failureCode = if ($accepted) {
        $null
    }
    elseif (-not $trusted.parsed) {
        "TRUSTED_$($trusted.failureCode)"
    }
    elseif (-not $observed.parsed) {
        "OBSERVED_$($observed.failureCode)"
    }
    else {
        'UTC_INSTANT_MISMATCH'
    }

    return [pscustomobject][ordered]@{
        trustedOriginalText = if ($null -eq $TrustedText) { $null } else { [string]$TrustedText }
        observedOriginalText = if ($null -eq $ObservedText) { $null } else { [string]$ObservedText }
        trusted = $trusted
        observed = $observed
        bothParsedUniquely = $bothParsedUniquely
        sameUtcInstant = $sameUtcInstant
        comparisonAccepted = $accepted
        failClosed = (-not $accepted)
        failureCode = $failureCode
        comparisonBasis = 'UTC_TICKS'
    }
}
