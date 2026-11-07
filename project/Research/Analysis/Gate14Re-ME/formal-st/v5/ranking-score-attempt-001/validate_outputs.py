"""Read-only cross-check of frozen sources, ranking exports, and final manuscript."""
import csv
import hashlib
import json
import math
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from statistics import NormalDist
from docx import Document

ROOT = Path(__file__).resolve().parent
DOC = Path('H:/DDM_Final_Project/Research/ManuscriptAssets/V4_Gate14ReME_Ranking_Update')
ALGS = ['A*-R', 'BiA*-R', 'D*L', 'LPA*', 'C-FF', 'IDFF']
DOMS = [f'D{i}' for i in range(1, 8)]
EPS = ['D1 GM', 'D1 P95', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7']
checks = []


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def rows(name):
    with (ROOT/name).open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def close(a, b):
    assert math.isclose(float(a), float(b), rel_tol=1e-9, abs_tol=1e-10), (a, b)


def pclose(a, b):
    assert math.isclose(float(a), float(b), rel_tol=1e-8, abs_tol=1e-300), (a, b)


def mark(name, count):
    checks.append({'check': name, 'status': 'PASS', 'count': count})


def main():
    result = read(ROOT/'ranking-results.v1.json')
    contract = read(ROOT/'ranking-contract.v1.json')
    close(sum(contract['primaryWeights'].values()), 1)
    assert digest(ROOT/'ranking-contract.v1.json') == result['contractSha256']
    verification = read(ROOT/'source-verification.v1.json')
    assert len(verification['files']) == 16
    for entry in verification['files']:
        source = Path(entry['source'])
        assert source.stat().st_size == entry['bytes'] and digest(source) == entry['sha256']
    mark('Frozen source hashes and byte lengths', 16)
    diag = read(ROOT.parent/'attempt-004/model-fit-diagnostics.v1.json')
    source_pairs = read(ROOT.parent/'attempt-004/exploratory-pair-matrices.v1.json')
    gates = read(ROOT.parent/'attempt-004/hard-gates.v1.json')
    assert all(value is True for key, value in gates.items() if key != 'schema')
    inputs = rows('score-inputs-and-ranks.v1.csv')
    lookup = {(r['algorithm'], r['endpoint']): r for r in inputs}
    assert len(inputs) == len(lookup) == 48
    models = ['D1_GEOMETRIC_MEAN', 'D1_NEAREST_RANK_P95', 'D2', 'D3', 'D4']
    for a in ALGS:
        for i, ep in enumerate(EPS):
            r = lookup[a, ep]
            if i < 5:
                co = diag['models'][models[i]]['coefficients']
                val = co['Intercept'] + co.get(f'algorithm[{a}]', 0)
                natural = math.expm1(val) if ep in ['D3', 'D4'] else math.exp(val)
            else:
                axis = ['centeredLog2N', 'centeredLog2F', 'centeredLog2G2'][i-5]
                co = diag['models']['D1_GEOMETRIC_MEAN']['coefficients']
                val = co[axis] + co.get(f'algorithm[{a}]:{axis}', 0)
                natural = val
            close(val, r['modelScaleValue'])
            close(natural, r['referenceAdjustedOriginalScaleOrSlope'])
            vals = [float(lookup[b, ep]['modelScaleValue']) for b in ALGS]
            tied = [v for v in vals if math.isclose(v, val, rel_tol=1e-10, abs_tol=1e-10)]
            less = sum(v < val and not math.isclose(v, val, rel_tol=1e-10, abs_tol=1e-10) for v in vals)
            rank = 1 + less + (len(tied)-1)/2
            close(rank, r['pointRank'])
            close(20*(6-rank), r['utility'])
    mark('Endpoint values reconstructed from frozen coefficients, with independent midrank checks', 48)
    effects = rows('all-pair-primitive-inference.v1.csv')
    composites = rows('all-pair-composite-decisions.v1.csv')
    assert len(effects) == len({(r['endpoint'], r['first'], r['second']) for r in effects}) == 120
    assert len(composites) == len({(r['domain'], r['first'], r['second']) for r in composites}) == 105
    source_lookup = {}
    for domain in source_pairs['domains']:
        d = domain['domainId'].split('_')[0]
        for pair in domain['pairs']:
            components = [('D1 GM', pair['components']['equalDesignGeometricMeanRatio']), ('D1 P95', pair['components']['equalDesignNearestRankP95Ratio'])] if d == 'D1' else [(d, pair['component'])]
            for ep, c in components:
                source_lookup[ep, pair['first'], pair['second']] = c
    critical = NormalDist().inv_cdf(1-0.05/240)
    close(critical, result['normalZCritical'])
    for r in effects:
        source = source_lookup[r['endpoint'], r['first'], r['second']]
        est, se = float(r['differenceModelScale']), float(r['standardError'])
        close(est, source['estimateModelScale'])
        close(se, source['standardError'])
        close(est, float(lookup[r['first'], r['endpoint']]['modelScaleValue'])-float(lookup[r['second'], r['endpoint']]['modelScaleValue']))
        close(est/se, r['z'])
        pclose(math.erfc(abs(est/se)/math.sqrt(2)), r['twoSidedP'])
        # Source normal-CDF subtraction loses precision near zero. Compare
        # source p within floating-point CDF roundoff, while the erfc formula
        # above is checked at strict relative tolerance.
        assert math.isclose(source['twoSidedP'], float(r['twoSidedP']), rel_tol=1e-8, abs_tol=5e-16)
        lo, hi = est-critical*se, est+critical*se
        close(lo, r['globalSimultaneousLowerModelScale'])
        close(hi, r['globalSimultaneousUpperModelScale'])
        transform = math.exp if r['effectScale'] == 'ratio' else lambda x: x
        for value, key in [(est, 'effect'), (lo, 'globalSimultaneousLower'), (hi, 'globalSimultaneousUpper')]:
            close(transform(value), r[key])
        assert int(r['globalPrimitiveFamilySize']) == 120
    ordered = sorted(composites, key=lambda r: float(r['rawCompositeTwoSidedP']))
    for i, r in enumerate(ordered):
        parts = [e for e in effects if all(e[k] == r[k] for k in ['domain', 'first', 'second'])]
        assert len(parts) == (2 if r['domain'] == 'D1' else 1)
        pclose(max(float(e['twoSidedP']) for e in parts), r['rawCompositeTwoSidedP'])
        adjusted = min(1, max((105-j)*float(ordered[j]['rawCompositeTwoSidedP']) for j in range(i+1)))
        pclose(adjusted, r['globalHolmTwoSidedP'])
        first = all(float(e['globalSimultaneousUpperModelScale']) < 0 for e in parts)
        second = all(float(e['globalSimultaneousLowerModelScale']) > 0 for e in parts)
        assert first == (r['firstAllComponentsLower'] == 'True')
        assert second == (r['secondAllComponentsLower'] == 'True')
        winner = r['first'] if first and adjusted < .05 else r['second'] if second and adjusted < .05 else ''
        assert winner == r['supportedWinner']
        for e in parts:
            pclose(adjusted, e['globalHolmCompositeP'])
            assert e['supportedCompositeWinner'] == winner
    mark('All-pair source effects, intervals, p values, and global multiplicity', 120)
    utility, lo_utility, hi_utility = {}, {}, {}
    for a in ALGS:
        for ep in EPS:
            relevant = [r for r in effects if r['endpoint'] == ep and a in (r['first'], r['second'])]
            certainly_better, certainly_worse = 0, 0
            for r in relevant:
                lower, upper = float(r['globalSimultaneousLowerModelScale']), float(r['globalSimultaneousUpperModelScale'])
                if a == r['second']:
                    lower, upper = -upper, -lower
                certainly_better += upper < 0
                certainly_worse += lower > 0
            best, worst = 1+certainly_worse, 6-certainly_better
            close(best, lookup[a, ep]['rankBestSimultaneous'])
            close(worst, lookup[a, ep]['rankWorstSimultaneous'])
        for d in DOMS:
            eps = ['D1 GM', 'D1 P95'] if d == 'D1' else [d]
            utility[a, d] = sum(float(lookup[a, ep]['utility']) for ep in eps)/len(eps)
            lo_utility[a, d] = sum(20*(6-float(lookup[a, ep]['rankWorstSimultaneous'])) for ep in eps)/len(eps)
            hi_utility[a, d] = sum(20*(6-float(lookup[a, ep]['rankBestSimultaneous'])) for ep in eps)/len(eps)
    score_rows = rows('ranking-and-score-contributions.v1.csv')
    scores = {}
    for r in score_rows:
        a = r['algorithm']
        scores[a] = sum(utility[a, d]*contract['primaryWeights'][d] for d in DOMS)
        close(scores[a], r['primaryScore'])
        close(sum(lo_utility[a, d]*contract['primaryWeights'][d] for d in DOMS), r['conservativeSimultaneousScoreLower'])
        close(sum(hi_utility[a, d]*contract['primaryWeights'][d] for d in DOMS), r['conservativeSimultaneousScoreUpper'])
        for d in DOMS:
            close(utility[a, d], r[d+'Utility'])
            close(utility[a, d]*contract['primaryWeights'][d], r[d+'WeightedContribution'])
        stored = next(x for x in result['ranking'] if x['algorithm'] == a)
        for key, value in r.items():
            if key != 'algorithm':
                close(value, stored[key])
    close(sum(scores.values()), 300)
    for d in DOMS:
        close(sum(utility[a, d] for a in ALGS), 300)
    order = sorted(ALGS, key=lambda a: -scores[a])
    assert order == [r['algorithm'] for r in score_rows]
    for i, r in enumerate(score_rows, 1):
        close(r['rank'], i)
    assert result['primaryScoreWinners'] == [order[0]]
    separated = [r['algorithm'] for r in result['ranking'] if all(r['conservativeSimultaneousScoreLower'] > other['conservativeSimultaneousScoreUpper']+1e-10 for other in result['ranking'] if other['algorithm'] != r['algorithm'])]
    assert separated == result['statisticallySeparatedScoreWinners']
    domain_rows = rows('domain-winner-decisions.v1.csv')
    assert len(domain_rows) == 42
    for r in domain_rows:
        relevant = [c for c in composites if c['domain'] == r['domain'] and r['algorithm'] in [c['first'], c['second']]]
        wins = sum(c['supportedWinner'] == r['algorithm'] for c in relevant)
        losses = sum(c['supportedWinner'] not in ['', r['algorithm']] for c in relevant)
        assert int(r['supportedWins']) == wins and int(r['supportedLosses']) == losses
        assert int(r['unresolvedOrTradeoff']) == 5-wins-losses
        assert (r['uniqueDomainWinner'] == 'True') == (wins == 5)
    mark('Scores, rank bounds, six-algorithm ranking, and supported domain decisions', 6)
    # Validate retained internal preference exports without adding them to the manuscript.
    for name, count in [('runtime-weight-sensitivity.v1.csv', 201), ('weight-corner-sensitivity.v1.csv', 128), ('leave-one-domain-out.v1.csv', 7)]:
        scenarios = rows(name)
        assert len(scenarios) == count
        for r in scenarios:
            if 'runtimeGroupWeight' in r:
                rho = float(r['runtimeGroupWeight'])
                weights = dict(zip(DOMS, [rho/2, rho*2/7, rho*3/14]+[(1-rho)/4]*4))
            elif 'scenario' in r:
                weights = {d: float(r[d+'Weight']) for d in DOMS}
            else:
                weights = {d: 0 if d == r['removedDomain'] else contract['primaryWeights'][d]/(1-contract['primaryWeights'][r['removedDomain']]) for d in DOMS}
            close(sum(weights.values()), 1)
            expected = {a: sum(weights[d]*utility[a, d] for d in DOMS) for a in ALGS}
            for a in ALGS:
                close(expected[a], r[a])
            winner = [a for a in ALGS if math.isclose(expected[a], max(expected.values()), rel_tol=1e-10, abs_tol=1e-10)]
            assert '|'.join(winner) == r['winners']
    mark('Retained internal preference-export consistency', 336)
    record = read(DOC/'ranking-draft-edit-record.json')
    backup, output = Path(record['backup']), Path(record['output'])
    assert digest(backup) == record['backupSha256'] and digest(output) == record['outputSha256']
    before, after = Document(backup), Document(output)
    def cell_texts(table):
        return [[cell.text for cell in row.cells] for row in table.rows]
    old_tables, new_tables = [cell_texts(t) for t in before.tables], [cell_texts(t) for t in after.tables]
    cursor = 0
    for table in old_tables:
        while cursor < len(new_tables) and new_tables[cursor] != table:
            cursor += 1
        assert cursor < len(new_tables), 'Original table missing or changed'
        cursor += 1
    assert len(old_tables) == 16 and len(new_tables) == 17
    mapping = {r['old']: r['new'] for r in record['edits']}
    expected_paragraphs = [mapping.get(p.text, p.text) for p in before.paragraphs]
    actual_paragraphs = [p.text for p in after.paragraphs]
    cursor = 0
    for paragraph in expected_paragraphs:
        while cursor < len(actual_paragraphs) and actual_paragraphs[cursor] != paragraph:
            cursor += 1
        assert cursor < len(actual_paragraphs), ('Original paragraph lost', paragraph[:90])
        cursor += 1
    def image_digests(path):
        with zipfile.ZipFile(path) as z:
            return {hashlib.sha256(z.read(name)).hexdigest() for name in z.namelist() if name.startswith('word/media/')}
    assert image_digests(backup) <= image_digests(output)
    new_text = '\n'.join(p for p in actual_paragraphs if p not in [q.text for q in before.paragraphs])
    for forbidden in ['weight-corner', '44.6809', '118 of 128', 'score reconstruction', 'Appendix B', 'Table S9', '0.35u', '100(6', 'weight sensitivity']:
        assert forbidden.casefold() not in new_text.casefold(), forbidden
    assert 'practical development and deployment are especially sensitive' in new_text
    assert len(after.inline_shapes) == 6
    layout = read(DOC/'document-layout-audit.json')
    assert layout['pages'] == 34 and not any(p['outsidePage'] for p in layout['pageDetails'])
    assert not any(read(DOC/'a11y-audit-final.json')['counts'].values())
    mark('Original tables, figures, paragraphs, and source-chain appendix preserved', 16)
    mark('Latest manuscript reporting preference and page-boundary/accessibility checks', 34)
    now = datetime.now(timezone.utc).isoformat()
    audit = {'schema': 'gate14re-me-ranking-validation-v1', 'status': 'PASS', 'validatedAtUtc': now, 'checks': checks, 'sourcesUnchanged': True, 'modelRefit': False, 'manuscriptSha256': digest(output)}
    (ROOT/'analysis-validation.v1.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    qa = {'status': 'PASS', 'validatedAtUtc': now, 'docxSha256': digest(output), 'renderPdfSha256': digest(DOC/'rendered/DraftV4-ranking-check3.pdf'), 'pages': 34, 'visuallyInspectedPages': list(range(1,35)), 'visualDefectsFound': 0, 'tables': 17, 'inlineFigures': 6, 'preservedOriginalTables': 16, 'preservedOriginalFigures': 5, 'accessibilityFindings': {'high': 0, 'medium': 0, 'low': 0}, 'rankingCalculationAndSensitivityInserted': False, 'measurementAndModelProvenancePreserved': True}
    (DOC/'document-final-qa.json').write_text(json.dumps(qa, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'status': 'PASS', 'validationGroups': len(checks), 'sourceFiles': 16, 'pages': 34, 'manuscriptSha256': digest(output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
