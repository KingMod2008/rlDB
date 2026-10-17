    const launcher = document.getElementById('launcher');
    const panel = document.getElementById('panel');
    const empty = document.getElementById('empty');
    const content = document.getElementById('content');
    const scoreboard = document.getElementById('scoreboard');
    const timelineShell = document.getElementById('timeline-shell');
    const timeline = document.getElementById('timeline');
    const timelineLeft = document.getElementById('timeline-left');
    const timelineRight = document.getElementById('timeline-right');
    const ratios = document.getElementById('ratios');
    const overview = document.getElementById('overview');
    const teamsView = document.getElementById('teams');
    const formView = document.getElementById('form');
    const scoreboardTab = document.getElementById('scoreboard-tab');
    const overviewTab = document.getElementById('overview-tab');
    const timelineTab = document.getElementById('timeline-tab');
    const ratiosTab = document.getElementById('ratios-tab');
    const teamsTab = document.getElementById('teams-tab');
    const formTab = document.getElementById('form-tab');
    const closeButton = document.getElementById('close');
    const analysisHint = document.getElementById('analysis-hint');
    const navButtons = Array.from(document.querySelectorAll('.nav'));
    let latestMessage = { visible: false, matches: [] };
    let localOpen = false;
    let localTab = 'scoreboard';
    let localMatch = 1;
    let analyticsPlayer = '';
    let panelClosing = false;
    let closeTimer = 0;
    let analysisHintShown = false;
    let analysisHintTimer = 0;

    function safeNumber(value) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
    function total(players, field, team) { return players.filter(player => team === undefined || safeNumber(player.team) === team).reduce((sum, player) => sum + safeNumber(player[field]), 0); }
    function percent(numerator, denominator) { return denominator > 0 ? `${Math.round(numerator / denominator * 100)}%` : '—'; }
    function teamName(team) { return safeNumber(team) === 0 ? 'Blue' : safeNumber(team) === 1 ? 'Orange' : 'Unknown'; }
    function formatElapsed(seconds) { seconds = Math.max(0, Math.round(safeNumber(seconds))); return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`; }
    const playlistNames = {
      1:'Duel - Casual', 2:'Doubles - Casual', 3:'Standard - Casual', 4:'Chaos - Casual', 6:'Private Match',
      10:'Duel - Competitive', 11:'Doubles - Competitive', 13:'Standard - Competitive', 15:'Snow Day - Casual',
      17:'Hoops - Casual', 18:'Rumble - Casual', 19:'Dropshot - Casual', 22:'Tournament', 24:'Dropshot - Competitive',
      27:'Hoops - Competitive', 28:'Rumble - Competitive', 29:'Snow Day - Competitive', 30:'Dropshot - Competitive',
      34:'Tournament', 38:'Heatseeker - Casual', 43:'Heatseeker Doubles - Casual', 46:'Gridiron - Casual',
      47:'Knockout - Casual', 63:'Heatseeker Doubles - Competitive', 92:'Bullet Ball Casual'
    };
    const arenaNames = {
      'ARC_P':'Starbase ARC', 'AquaDome_P':'Aquadome', 'Beach_P':'Salty Shores', 'Beach_Night_P':'Salty Shores (Night)',
      'CHN_Stadium_P':'Forbidden Temple', 'CHN_Stadium_Day_P':'Forbidden Temple (Day)', 'DeadeyeCanyon_P':'Deadeye Canyon',
      'EuroStadium_P':'Mannfield', 'EuroStadium_Night_P':'Mannfield (Night)', 'EuroStadium_Rainy_P':'Mannfield (Stormy)',
      'Farm_P':'Farmstead', 'Farm_Night_P':'Farmstead (Night)', 'HoopsStadium_P':'Dunk House', 'Street_P':'The Block',
      'Labs_CirclePillars_P':'Pillars', 'Labs_Cosmic_P':'Cosmic', 'Labs_DoubleGoal_P':'Double Goal', 'Labs_Octagon_02_P':'Octagon',
      'Labs_Underpass_P':'Underpass', 'Labs_Utopia_P':'Utopia Retro', 'MusicStadium_P':'Neon Fields',
      'NeoTokyo_P':'Neo Tokyo', 'NeoTokyo_Standard_P':'Neo Tokyo', 'NeoTokyo_Hax_P':'Neo Tokyo',
      'Park_P':'Beckwith Park', 'Park_Night_P':'Beckwith Park (Midnight)', 'Park_Rainy_P':'Beckwith Park (Stormy)',
      'Stadium_P':'DFH Stadium', 'Stadium_Foggy_P':'DFH Stadium (Stormy)', 'Stadium_Winter_P':'DFH Stadium (Snowy)',
      'TrainStation_P':'Urban Central', 'TrainStation_Dawn_P':'Urban Central (Dawn)', 'TrainStation_Night_P':'Urban Central (Night)',
      'Underwater_P':'Aquadome', 'UtopiaStadium_P':'Utopia Coliseum', 'UtopiaStadium_Dusk_P':'Utopia Coliseum (Dusk)',
      'Wasteland_P':'Wasteland', 'Wasteland_Night_P':'Wasteland (Night)', 'ThrowbackStadium_P':'Throwback Stadium',
      'CS_P':'Champions Field', 'ChampionsField_P':'Champions Field', 'Haunted_TrainStation_P':'Urban Central (Haunted)'
    };
    function playlistName(id) { id = safeNumber(id); return playlistNames[id] || `Playlist ${id}`; }
    function arenaName(raw) { const value=String(raw||''); const key=Object.keys(arenaNames).find(item=>item.toLowerCase()===value.toLowerCase()); if(key) return arenaNames[key]; return value.replace(/_P$/i,'').replace(/_/g,' ').replace(/\b\w/g,char=>char.toUpperCase()) || 'Unknown arena'; }

    function appendRankIdentity(container, player) {
      if (!player.rank_name && player.rank_tier_id == null && player.rank_mmr == null) return;
      const tier = Math.max(0, Math.min(23, Math.floor(safeNumber(player.rank_tier_id))));
      if (player.rank_tier_id != null) {
        const rankIcon = document.createElement('img'); rankIcon.className = 'rank-icon'; rankIcon.src = `tiers/${tier}.png`; rankIcon.alt = player.rank_name || 'Rank'; rankIcon.title = player.rank_name || 'Rank'; container.appendChild(rankIcon);
        if (tier > 0 && tier < 22 && player.rank_division_id != null) {
          const division = Math.max(0, Math.min(3, Math.floor(safeNumber(player.rank_division_id))));
          const colour = Math.max(1, Math.min(7, Math.floor((tier - 1) / 3) + 1));
          const divisionIcon = document.createElement('span'); divisionIcon.className = 'division-icon'; divisionIcon.title = `Division ${division + 1}`;
          for (let slot = 3; slot >= 0; slot -= 1) { const pip = document.createElement('img'); pip.src = `divisions/${slot <= division ? colour : 0}.png`; pip.alt = ''; divisionIcon.appendChild(pip); }
          container.appendChild(divisionIcon);
        }
      } else if (player.rank_name) {
        const fallback = document.createElement('span'); fallback.className = 'rank-badge'; fallback.textContent = player.rank_name; container.appendChild(fallback);
      }
      if (player.rank_mmr != null) { const mmr = document.createElement('span'); mmr.className = 'rank-mmr'; mmr.textContent = `[${Math.round(safeNumber(player.rank_mmr))}]`; container.appendChild(mmr); }
    }
    function renderFinalScoreboard(match) {
      scoreboard.textContent='';
      const board=document.createElement('section'); board.className='final-board'; const players=Array.isArray(match.players)?match.players:[];
      if(!players.length){const empty=document.createElement('div');empty.className='board-empty';empty.textContent='No scoreboard snapshot was available.';board.appendChild(empty);scoreboard.appendChild(board);return;}
      [0,1].forEach(teamNumber=>{const team=document.createElement('section');team.className=`final-team team-${teamNumber}`;const teamInfo=(Array.isArray(match.teams)?match.teams:[]).find(item=>safeNumber(item.team)===teamNumber)||{};const head=document.createElement('div');head.className='final-team-head';['','Score','Goals','Assists','Saves','Shots','Demos'].forEach((text,index)=>{const cell=document.createElement('span');cell.textContent=index===0?`${teamInfo.name||teamName(teamNumber)} · ${safeNumber(teamInfo.score)}`:text;if(index===0)cell.className='final-team-title';head.appendChild(cell);});team.appendChild(head);
        players.filter(player=>safeNumber(player.team)===teamNumber).sort((a,b)=>Number(Boolean(a.left))-Number(Boolean(b.left))||safeNumber(b.score)-safeNumber(a.score)||safeNumber(b.goals)-safeNumber(a.goals)||String(a.name||'').localeCompare(String(b.name||''))).forEach(player=>{const row=document.createElement('div');row.className='final-player';const local=String(player.id||'')===String(match.local_platform_id||'__no_local__');if(local)row.classList.add('local-player');if(player.left)row.classList.add('left-player');const nameCell=document.createElement('span');nameCell.className='final-name';appendRankIdentity(nameCell,player);const playerName=document.createElement('span');playerName.className='player-name';playerName.textContent=player.name||'Player';nameCell.appendChild(playerName);if(local){const you=document.createElement('span');you.className='player-state';you.textContent='YOU';nameCell.appendChild(you);}if(player.left){const left=document.createElement('span');left.className='player-state';left.textContent='LEFT';nameCell.appendChild(left);}row.appendChild(nameCell);[['score','stat-score'],['goals','stat-goals'],['assists',''],['saves',''],['shots',''],['demos','']].forEach(([field,className])=>{const cell=document.createElement('span');cell.className=className;cell.textContent=safeNumber(player[field]);row.appendChild(cell);});team.appendChild(row);});board.appendChild(team);});scoreboard.appendChild(board);
    }
    function ratioCard(label, value, note) { const card = document.createElement('div'); card.className = 'ratio-card'; card.innerHTML = '<div class="ratio-label"></div><div class="ratio-value"></div><div class="ratio-note"></div>'; card.children[0].textContent = label; card.children[1].textContent = value; card.children[2].textContent = note; return card; }

    function enrichedEvents(match) {
      const sourceEvents = Array.isArray(match.events) ? match.events : [];
      const events = sourceEvents.map((item, index) => ({ ...item, originalIndex: index })).sort((a, b) => safeNumber(a.elapsed) - safeNumber(b.elapsed) || safeNumber(a.sequence) - safeNumber(b.sequence));
      events.forEach(item => {
        if (item.related) return;
        const elapsed = safeNumber(item.elapsed);
        if (String(item.kind).toLowerCase() === 'save') {
          const shot = events.filter(candidate => String(candidate.kind).toLowerCase() === 'shot' && safeNumber(candidate.team) !== safeNumber(item.team) && Math.abs(safeNumber(candidate.elapsed) - elapsed) <= 3).sort((a, b) => Math.abs(safeNumber(a.elapsed) - elapsed) - Math.abs(safeNumber(b.elapsed) - elapsed))[0];
          if (shot) { item.related = shot.player; item.related_team = shot.team; item.relation = 'saved a shot by'; }
        } else if (String(item.kind).toLowerCase() === 'shot') {
          const save = events.filter(candidate => String(candidate.kind).toLowerCase() === 'save' && safeNumber(candidate.team) !== safeNumber(item.team) && Math.abs(safeNumber(candidate.elapsed) - elapsed) <= 3).sort((a, b) => Math.abs(safeNumber(a.elapsed) - elapsed) - Math.abs(safeNumber(b.elapsed) - elapsed))[0];
          if (save) { item.related = save.player; item.related_team = save.team; item.relation = 'saved by'; }
        }
      });
      return events;
    }

    function eventDetail(item) {
      const kind=String(item.kind||'').toLowerCase();
      if(kind==='overtime')return 'Extra time began';
      if(item.reconciled)return 'Recovered from final scoreboard · exact time unavailable';
      if(kind==='player left')return ` · disconnected`;
      if(kind==='player joined')return ` · joined the match`;
      if(kind==='player rejoined')return ` · rejoined the match`;
      const pieces = [teamName(item.team)];
      if (item.related) pieces.push(`${item.relation || 'with'} ${item.related}`);
      if (safeNumber(item.goal_speed) > 0) pieces.push(`${Math.round(safeNumber(item.goal_speed))} km/h`);
      return pieces.join(' · ');
    }

    function renderTimeline(match) {
      timeline.textContent = '';
      const events = enrichedEvents(match);
      if (!events.length) {
        const row = document.createElement('div'); row.className = 'meta'; row.style.padding = '18px'; row.textContent = 'No tracked events occurred in this match.'; timeline.appendChild(row); requestAnimationFrame(updateTimelineButtons); return;
      }

      const maxElapsed = Math.max(1, safeNumber(match.duration_seconds), ...events.map(item => safeNumber(item.elapsed)));
      const trackWidth = Math.max(timeline.clientWidth - 2, events.length * 150, maxElapsed * 8);
      const track = document.createElement('div'); track.className = 'timeline-track'; track.style.width = `${trackWidth}px`;
      const axis = document.createElement('div'); axis.className = 'axis'; axis.innerHTML = '<div class="axis-progress"></div>'; track.appendChild(axis);
      const legend = document.createElement('div'); legend.className = 'legend'; legend.innerHTML = '<span><i></i>Shot</span><span class="goal"><i></i>Goal</span><span class="save"><i></i>Save</span><span class="demo"><i></i>Demo</span>'; track.appendChild(legend);

      for (let tickIndex = 0; tickIndex <= 4; tickIndex += 1) {
        const tick = document.createElement('span'); tick.className = 'tick'; tick.style.left = `${48 + (trackWidth - 96) * (tickIndex / 4)}px`; tick.textContent = formatElapsed(maxElapsed * tickIndex / 4); track.appendChild(tick);
      }

      const laneLastX = [-Infinity, -Infinity, -Infinity, -Infinity];
      events.forEach((item, index) => {
        const axisX = 48 + (trackWidth - 96) * (safeNumber(item.elapsed) / maxElapsed);
        const preferred = safeNumber(item.team) === 1 ? [2, 3, 0, 1] : [0, 1, 2, 3];
        let lane = preferred.find(candidate => axisX - laneLastX[candidate] >= 194);
        if (lane === undefined) lane = preferred.reduce((best, candidate) => laneLastX[candidate] < laneLastX[best] ? candidate : best, preferred[0]);
        laneLastX[lane] = axisX;
        const above = lane < 2;
        const lanePosition = [40, 127, 282, 369][lane];
        const connector = above ? 220 - lanePosition - 78 : lanePosition - 220;
        const kind = String(item.kind || 'Event').toLowerCase();

        const marker = document.createElement('button'); marker.className = `marker ${kind} team-${safeNumber(item.team)}`; marker.style.left = `${axisX}px`; marker.title = `${formatElapsed(item.elapsed)} · ${item.kind || 'Event'} · ${item.player || 'Player'} · ${eventDetail(item)}`; marker.addEventListener('click', () => card.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' }));

        const card = document.createElement('article'); card.className = `event-card ${above ? 'above' : 'below'} ${safeNumber(item.team) === 1 ? 'team-orange' : 'team-blue'}`; card.style.left = `${axisX}px`; card.style.top = `${lanePosition}px`; card.style.setProperty('--connector', `${Math.max(4, connector)}px`);
        const head = document.createElement('div'); head.className = 'event-head'; const badge = document.createElement('span'); badge.className = `badge ${kind}`; badge.textContent = item.kind || 'Event'; const clock = document.createElement('span'); clock.className = 'clock'; clock.textContent = formatElapsed(item.elapsed); head.append(badge, clock);
        const player = document.createElement('div'); player.className = 'player'; player.textContent = item.player || 'Player'; const detail = document.createElement('div'); detail.className = 'event-detail'; detail.textContent = eventDetail(item); card.append(head, player, detail);
        track.append(marker, card);
      });
      timeline.appendChild(track);
      requestAnimationFrame(updateTimelineButtons);
    }

    function analyticsPlayerKey(player, index) { return String(player.id || `${player.name || 'Player'}:${index}`); }

    function createFlowChart(match, player) {
      const card = document.createElement('section'); card.className = 'chart-card wide';
      const title = document.createElement('div'); title.className = 'chart-title'; title.textContent = 'Event flow'; card.appendChild(title);
      const ns = 'http://www.w3.org/2000/svg'; const svg = document.createElementNS(ns, 'svg'); svg.classList.add('flow-chart'); svg.setAttribute('viewBox', '0 0 900 165');
      const left = 28, right = 886, top = 12, bottom = 142;
      for (let row = 0; row <= 4; row += 1) { const line = document.createElementNS(ns, 'line'); line.setAttribute('x1', left); line.setAttribute('x2', right); line.setAttribute('y1', top + (bottom-top)*row/4); line.setAttribute('y2', top + (bottom-top)*row/4); line.setAttribute('class', 'flow-grid'); svg.appendChild(line); }
      const events = enrichedEvents(match).filter(item => String(item.player || '') === String(player.name || ''));
      const duration = Math.max(1, safeNumber(match.duration_seconds), ...events.map(item => safeNumber(item.elapsed)));
      const series = [['Shot','#21a8ff'],['Goal','#ff9f35'],['Assist','#bb7cff'],['Save','#4fdda2']];
      const maximum = Math.max(1, ...series.map(([kind]) => events.filter(item => String(item.kind).toLowerCase() === kind.toLowerCase()).length));
      series.forEach(([kind, colour]) => { const relevant = events.filter(item => String(item.kind).toLowerCase() === kind.toLowerCase()).sort((a,b) => safeNumber(a.elapsed)-safeNumber(b.elapsed)); let count=0; const points=[`${left},${bottom}`]; relevant.forEach(item => { count+=1; points.push(`${left+(right-left)*safeNumber(item.elapsed)/duration},${bottom-(bottom-top)*count/maximum}`); }); if(relevant.length) points.push(`${right},${bottom-(bottom-top)*count/maximum}`); const line=document.createElementNS(ns,'polyline'); line.setAttribute('points',points.join(' ')); line.setAttribute('class','flow-line'); line.setAttribute('stroke',colour); svg.appendChild(line); });
      card.appendChild(svg); const labels=document.createElement('div'); labels.className='flow-labels'; series.forEach(([kind,colour]) => { const label=document.createElement('span'); label.style.setProperty('--colour',colour); label.textContent=kind; labels.appendChild(label); }); card.appendChild(labels); return card;
    }

    function renderAnalytics(match) {
      ratios.textContent = '';
      const players = Array.isArray(match.players) ? match.players : [];
      if (!players.length) { ratios.appendChild(ratioCard('No player data','—','No final player snapshot was recorded.')); return; }
      const indexed = players.map((player,index) => ({player,key:analyticsPlayerKey(player,index)}));
      if (!indexed.some(item => item.key === analyticsPlayer)) { const local=indexed.find(item => match.local_platform_id && String(item.player.id||'').toLowerCase() === String(match.local_platform_id).toLowerCase()); analyticsPlayer=(local||indexed[0]).key; }
      const selected=indexed.find(item => item.key === analyticsPlayer)||indexed[0], player=selected.player;
      const toolbar=document.createElement('div'); toolbar.className='analytics-toolbar';
      const label=document.createElement('label'); label.textContent='Player analysis';
      const picker=document.createElement('div'); picker.className='player-picker';
      const toggle=document.createElement('button'); toggle.className='player-picker-toggle'; toggle.textContent=`${player.name||'Player'} · ${teamName(player.team)}`;
      const options=document.createElement('div'); options.className='player-picker-options hidden';
      indexed.forEach(item=>{
        const option=document.createElement('button');
        option.className=`player-option${item.key===selected.key?' active':''}`;
        option.textContent=`${item.player.name||'Player'} · ${teamName(item.player.team)}`;
        option.addEventListener('click',event=>{ event.stopPropagation(); analyticsPlayer=item.key; renderAnalytics(match); });
        options.appendChild(option);
      });
      toggle.addEventListener('click',event=>{ event.stopPropagation(); options.classList.toggle('hidden'); });
      picker.append(toggle,options); toolbar.append(label,picker); ratios.appendChild(toolbar);
      const goals=safeNumber(player.goals), assists=safeNumber(player.assists), saves=safeNumber(player.saves), styleTotal=goals+assists+saves; const goalEnd=styleTotal?goals/styleTotal*100:0, assistEnd=styleTotal?(goals+assists)/styleTotal*100:0;
      const style=document.createElement('section'); style.className='chart-card'; style.innerHTML='<div class="chart-title">Playstyle contribution</div><div class="playstyle-layout"><div class="playstyle-ring"><div class="playstyle-total"></div></div><div class="chart-legend"></div></div>'; const ring=style.querySelector('.playstyle-ring'); ring.style.background=styleTotal?`conic-gradient(#ff9f35 0 ${goalEnd}%,#bb7cff ${goalEnd}% ${assistEnd}%,#4fdda2 ${assistEnd}% 100%)`:'#26343f'; const totalNode=style.querySelector('.playstyle-total'); totalNode.textContent=styleTotal; const small=document.createElement('small'); small.textContent='key actions'; totalNode.appendChild(small); const legend=style.querySelector('.chart-legend'); [['Goals',goals,'#ff9f35'],['Assists',assists,'#bb7cff'],['Saves',saves,'#4fdda2']].forEach(([name,count,colour])=>{const row=document.createElement('span'), nameNode=document.createElement('span'), dot=document.createElement('i'), valueNode=document.createElement('b'); dot.style.background=colour; nameNode.append(dot,document.createTextNode(name)); valueNode.textContent=count; row.append(nameNode,valueNode); legend.appendChild(row);}); ratios.appendChild(style);
      const shots=safeNumber(player.shots), misses=Math.max(0,shots-goals), conversion=shots?Math.min(100,goals/shots*100):0; const shot=document.createElement('section'); shot.className='chart-card'; shot.innerHTML='<div class="chart-title">Shot tracking</div><div class="shot-value"></div><div class="shot-track"><div class="shot-fill"></div></div><div class="shot-stats"><span></span><span></span><span></span></div>'; shot.querySelector('.shot-value').textContent=shots?`${Math.round(conversion)}%`:'—'; const note=document.createElement('span'); note.textContent=' conversion'; shot.querySelector('.shot-value').appendChild(note); shot.querySelector('.shot-fill').style.width=`${conversion}%`; const shotStats=shot.querySelectorAll('.shot-stats span'); shotStats[0].textContent=`${shots} shots`; shotStats[1].textContent=`${goals} goals`; shotStats[2].textContent=`${misses} saved/missed`; ratios.appendChild(shot);
      appendPlayerExtras(match,player);
      ratios.appendChild(createFlowChart(match,player)); const minutes=Math.max(1/60,safeNumber(match.duration_seconds)/60), summary=document.createElement('div'); summary.className='summary-grid'; summary.append(ratioCard('Goal involvement',String(goals+assists),`${goals} goals · ${assists} assists`),ratioCard('Saves per minute',(saves/minutes).toFixed(2),`${saves} saves in ${minutes.toFixed(1)} min`),ratioCard('Demos per minute',(safeNumber(player.demos)/minutes).toFixed(2),`${safeNumber(player.demos)} demolitions`),ratioCard('Tracked events',String(enrichedEvents(match).filter(item=>String(item.player||'')===String(player.name||'')).length),'Events involving this player')); ratios.appendChild(summary);
    }
    function card(title, wide) { const node=document.createElement('section');node.className=`data-card${wide?' wide':''}`;const heading=document.createElement('div');heading.className='data-title';heading.textContent=title;node.appendChild(heading);return node; }
    function bestPlayer(players, score) { return players.reduce((best,player)=>!best||score(player)>score(best)?player:best,null); }
    function displayNumber(value, digits=0) { const n=safeNumber(value); return digits ? n.toFixed(digits) : String(Math.round(n)); }
    function teamPlayers(match, team) { return (match.players||[]).filter(player=>safeNumber(player.team)===team); }
    function localPlayerFor(match) { return match.local_platform_id ? (match.players||[]).find(player=>String(player.id||'').toLowerCase()===String(match.local_platform_id).toLowerCase()) : undefined; }
    function winnerTeam(match) { const found=String(match.result||'').match(/team\s+(\d+)/i);if(found)return safeNumber(found[1]);const scores=match.teams||[];if(scores.length<2)return -1;const blue=scores.find(t=>safeNumber(t.team)===0),orange=scores.find(t=>safeNumber(t.team)===1);if(!blue||!orange||safeNumber(blue.score)===safeNumber(orange.score))return -1;return safeNumber(blue.score)>safeNumber(orange.score)?0:1; }
    function rankChange(match, player, index) { const older=(latestMessage.matches||[]).slice(index).find(item=>safeNumber(item.playlist_id)===safeNumber(match.playlist_id)&&(item.players||[]).some(other=>String(other.id||'')===String(player.id||'')));if(!older)return null;const previous=(older.players||[]).find(other=>String(other.id||'')===String(player.id||''));if(!previous||player.rank_mmr==null||previous.rank_mmr==null)return null;return safeNumber(player.rank_mmr)-safeNumber(previous.rank_mmr); }

    function awardNode(label, player, note) { const node=document.createElement('div');node.className='award';node.innerHTML='<div class="award-label"></div><div class="award-player"></div><div class="award-note"></div>';node.children[0].textContent=label;node.children[1].textContent=player?player.name||'Player':'—';node.children[2].textContent=note||'No qualifying data';return node; }
    function eventStreaks(match) { const result={};let last='',run=0;for(const event of enrichedEvents(match)){const kind=String(event.kind||'');const player=String(event.player||'');if(!['Shot','Goal','Save','Demo'].includes(kind))continue;const key=`${kind}:${player}`;run=key===last?run+1:1;last=key;const old=result[kind];if(!old||run>old.count)result[kind]={player,count:run};}return result; }
    function renderOverview(match,index) {
      overview.textContent='';const players=match.players||[],duration=Math.max(1,safeNumber(match.duration_seconds)),minutes=duration/60;
      const awards=document.createElement('div');awards.className='awards-grid';const mvp=bestPlayer(players,p=>safeNumber(p.score)),attacker=bestPlayer(players,p=>safeNumber(p.goals)*5+safeNumber(p.assists)*3+safeNumber(p.shots)),defender=bestPlayer(players,p=>safeNumber(p.saves)*4+safeNumber(p.score)/100),physical=bestPlayer(players,p=>safeNumber(p.demos));awards.append(awardNode('MVP',mvp,mvp?`${displayNumber(mvp.score)} score`:''),awardNode('Most offensive',attacker,attacker?`${displayNumber(attacker.goals)}G · ${displayNumber(attacker.shots)} shots`:''),awardNode('Most defensive',defender,defender?`${displayNumber(defender.saves)} saves`:''),awardNode('Most physical',physical,physical?`${displayNumber(physical.demos)} demos`:''));overview.appendChild(awards);
      const lead=card('Lead history');const line=document.createElement('div');line.className='lead-line';const history=Array.isArray(match.lead_history)?match.lead_history:[];if(history.length){history.forEach((entry,i)=>{const next=history[i+1];const segment=document.createElement('i');segment.className=`lead-segment ${safeNumber(entry.leader)===0?'blue':safeNumber(entry.leader)===1?'orange':''}`;segment.style.flexGrow=String(Math.max(1,safeNumber(next?next.elapsed:duration)-safeNumber(entry.elapsed)));segment.title=`${formatElapsed(entry.elapsed)} · ${entry.blue}-${entry.orange}`;line.appendChild(segment);});}else{line.innerHTML='<i class="lead-segment"></i>';}lead.appendChild(line);const caption=document.createElement('div');caption.className='lead-caption';caption.innerHTML=`<span>0:00</span><span>${match.overtime?'Overtime · ':''}${formatElapsed(duration)}</span>`;lead.appendChild(caption);overview.appendChild(lead);
      const streakCard=card('Best streaks');const streaks=eventStreaks(match),list=document.createElement('div');list.className='status-list';['Shot','Goal','Save','Demo'].forEach(kind=>{const row=document.createElement('div');row.className='status-item';const item=streaks[kind];row.innerHTML=`<span>${kind}s in succession</span><b>${item?`${item.count} · ${item.player}`:'—'}</b>`;list.appendChild(row);});streakCard.appendChild(list);overview.appendChild(streakCard);
      const status=card('Match state');const statusList=document.createElement('div');statusList.className='status-list';const left=players.filter(p=>p.left),rejoined=players.filter(p=>safeNumber(p.rejoin_count)>0);[['Duration',formatElapsed(duration)],['Overtime',match.overtime?`${formatElapsed(Math.max(0,duration-safeNumber(match.overtime_started_at)))} played`:'No'],['Departures',left.length?left.map(p=>p.name).join(', '):'None'],['Rejoined',rejoined.length?rejoined.map(p=>`${p.name} ×${p.rejoin_count}`).join(', '):'None']].forEach(([name,value])=>{const row=document.createElement('div');row.className='status-item';row.innerHTML=`<span>${name}</span><b></b>`;row.lastChild.textContent=value;statusList.appendChild(row);});status.appendChild(statusList);overview.appendChild(status);
      const involvement=card('Goal participation');const metric=document.createElement('div');metric.className='metric-list';players.slice().sort((a,b)=>safeNumber(b.goals)+safeNumber(b.assists)-safeNumber(a.goals)-safeNumber(a.assists)).forEach(player=>{const teamGoals=total(players,'goals',safeNumber(player.team)),pct=teamGoals?(safeNumber(player.goals)+safeNumber(player.assists))/teamGoals*100:0;const row=document.createElement('div');row.className=`metric-row ${safeNumber(player.team)===1?'orange':''}`;row.innerHTML='<span></span><div class="metric-track"><div class="metric-fill"></div></div><b class="metric-value"></b>';row.children[0].textContent=player.name||'Player';row.querySelector('.metric-fill').style.width=`${Math.min(100,pct)}%`;row.lastChild.textContent=`${Math.round(pct)}%`;metric.appendChild(row);});involvement.appendChild(metric);overview.appendChild(involvement);
      const local=localPlayerFor(match);const loadout=card('Local player snapshot');if(local){const delta=rankChange(match,local,index),status=document.createElement('div');status.className='status-list';const rank=`${local.rank_name||'Rank unavailable'}${local.rank_division?` · DIV ${local.rank_division}`:''}${local.rank_mmr!=null?` · ${Math.round(local.rank_mmr)} MMR`:''}`;const rankRow=document.createElement('div');rankRow.className='status-item';rankRow.innerHTML='<span>Rank</span><b></b>';rankRow.lastChild.textContent=rank;if(delta!=null){const change=document.createElement('span');change.className=`rank-change ${delta>=0?'up':'down'}`;change.textContent=` ${delta>=0?'+':''}${delta}`;rankRow.lastChild.appendChild(change);}status.appendChild(rankRow);loadout.appendChild(status);const grid=document.createElement('div');grid.className='loadout-grid';Object.entries(local.loadout||{}).forEach(([name,value])=>{const item=document.createElement('div');item.className='loadout-item';item.innerHTML='<small></small><span></span>';item.firstChild.textContent=name.replace('_',' ');item.lastChild.textContent=value;grid.appendChild(item);});loadout.appendChild(grid);}else loadout.append('No local player snapshot.');overview.appendChild(loadout);
    }

function compareRow(name,blue,orange,format=v=>displayNumber(v)) { blue=Math.max(0,safeNumber(blue));orange=Math.max(0,safeNumber(orange));const combined=blue+orange,row=document.createElement('div');row.className='compare-row';row.innerHTML='<b class="compare-blue"></b><div class="compare-middle"><span class="compare-label"></span><div class="compare-scale"><div class="compare-half blue"><i></i></div><span class="compare-zero">0</span><div class="compare-half orange"><i></i></div></div></div><b class="compare-orange"></b>';row.children[0].textContent=format(blue);row.children[1].querySelector('.compare-label').textContent=name;row.children[1].querySelector('.compare-half.blue i').style.width=`${combined?blue/combined*100:0}%`;row.children[1].querySelector('.compare-half.orange i').style.width=`${combined?orange/combined*100:0}%`;row.children[1].querySelector('.compare-scale').title=`Blue ${format(blue)} · Combined ${format(combined)} · Orange ${format(orange)}`;row.children[2].textContent=format(orange);return row; }
    function renderTeams(match) {
      teamsView.textContent='';const players=match.players||[],blue=teamPlayers(match,0),orange=teamPlayers(match,1),duration=Math.max(1,safeNumber(match.duration_seconds)),minutes=duration/60;
      const comparison=card('Blue vs Orange',true);[['Score','score'],['Goals','goals'],['Shots','shots'],['Assists','assists'],['Saves','saves'],['Demos','demos'],['Touches','touches']].forEach(([name,field])=>comparison.appendChild(compareRow(name,total(players,field,0),total(players,field,1))));comparison.appendChild(compareRow('Conversion',total(players,'shots',0)?total(players,'goals',0)/total(players,'shots',0)*100:0,total(players,'shots',1)?total(players,'goals',1)/total(players,'shots',1)*100:0,v=>`${Math.round(v)}%`));teamsView.appendChild(comparison);
      const boost=card('Boost management');const avg=list=>list.length?list.reduce((sum,p)=>sum+safeNumber(p.average_boost),0)/list.length:0;boost.append(compareRow('Average',avg(blue),avg(orange),v=>displayNumber(v,1)),compareRow('Collected',total(players,'boost_collected',0),total(players,'boost_collected',1)),compareRow('Used',total(players,'boost_used',0),total(players,'boost_used',1)),compareRow('Low boost',avg(blue.map(p=>({average_boost:p.low_boost_percent}))),avg(orange.map(p=>({average_boost:p.low_boost_percent}))),v=>`${Math.round(v)}%`));teamsView.appendChild(boost);
      const phases=card('Pressure by match phase');const events=enrichedEvents(match),third=duration/3;['Opening','Middle','Closing'].forEach((label,index)=>{const start=third*index,end=index===2?Infinity:third*(index+1);const relevant=events.filter(e=>safeNumber(e.elapsed)>=start&&safeNumber(e.elapsed)<end);const pressure=team=>relevant.filter(e=>safeNumber(e.team)===team).reduce((sum,e)=>sum+(e.kind==='Goal'?3:e.kind==='Shot'?2:e.kind==='Save'?1:0),0);phases.appendChild(compareRow(label,pressure(0),pressure(1)));});teamsView.appendChild(phases);
      const efficiency=card('Player efficiency',true);const table=document.createElement('table');table.className='mini-table';table.innerHTML='<thead><tr><th>Player</th><th>Score/min</th><th>Conversion</th><th>Save rate</th><th>Demos/min</th><th>Activity</th></tr></thead><tbody></tbody>';const opponentShots=team=>total(players,'shots',team===0?1:0);players.slice().sort((a,b)=>safeNumber(a.team)-safeNumber(b.team)||safeNumber(b.score)-safeNumber(a.score)).forEach(player=>{const row=document.createElement('tr');if(String(player.id||'')===String(match.local_platform_id||''))row.className='local';const values=[player.name||'Player',(safeNumber(player.score)/minutes).toFixed(0),percent(safeNumber(player.goals),safeNumber(player.shots)),percent(safeNumber(player.saves),opponentShots(safeNumber(player.team))),(safeNumber(player.demos)/minutes).toFixed(2),`${Math.round(safeNumber(player.activity_percent))}%`];values.forEach(value=>{const cell=document.createElement('td');cell.textContent=value;row.appendChild(cell);});table.tBodies[0].appendChild(row);});efficiency.appendChild(table);teamsView.appendChild(efficiency);
      const overtime=card('Regulation vs overtime',true);if(match.overtime&&match.overtime_baseline){const table=document.createElement('table');table.className='mini-table';table.innerHTML='<thead><tr><th>Player</th><th>OT score</th><th>OT goals</th><th>OT shots</th><th>OT saves</th><th>OT demos</th></tr></thead><tbody></tbody>';players.forEach(player=>{const base=match.overtime_baseline[String(player.id||'')]||{},row=document.createElement('tr');[player.name||'Player',safeNumber(player.score)-safeNumber(base.score),safeNumber(player.goals)-safeNumber(base.goals),safeNumber(player.shots)-safeNumber(base.shots),safeNumber(player.saves)-safeNumber(base.saves),safeNumber(player.demos)-safeNumber(base.demos)].forEach(value=>{const cell=document.createElement('td');cell.textContent=value;row.appendChild(cell);});table.tBodies[0].appendChild(row);});overtime.appendChild(table);}else overtime.append('This match did not reach overtime.');teamsView.appendChild(overtime);
    }

    function trendCard(title,values) { const node=card(title,true),ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');svg.classList.add('trend-chart');svg.setAttribute('viewBox','0 0 900 145');for(let i=0;i<4;i++){const line=document.createElementNS(ns,'line');line.setAttribute('x1','20');line.setAttribute('x2','880');line.setAttribute('y1',String(15+i*38));line.setAttribute('y2',String(15+i*38));line.setAttribute('class','trend-grid');svg.appendChild(line);}const max=Math.max(1,...values),min=Math.min(0,...values),range=Math.max(1,max-min),rawPoints=values.map((value,index)=>`${20+(values.length===1?0:860*index/(values.length-1))},${130-(safeNumber(value)-min)/range*110}`),points=values.length===1?[rawPoints[0],`880,${rawPoints[0].split(',')[1]}`]:rawPoints;const poly=document.createElementNS(ns,'polyline');poly.setAttribute('points',points.join(' '));poly.setAttribute('class','trend-line');svg.appendChild(poly);node.appendChild(svg);return node; }
    function renderForm(matches) {
      formView.textContent='';const entries=(matches||[]).map(match=>({match,player:localPlayerFor(match)})).filter(item=>item.player);if(!entries.length){const empty=card('Recent form',true);empty.append('No local-player match history is available yet.');formView.appendChild(empty);return;}const strip=document.createElement('div');strip.className='form-strip';entries.forEach(({match,player})=>{const winner=winnerTeam(match),team=safeNumber(player.team),result=winner<0?'D':winner===team?'W':'L',node=document.createElement('div');node.className=`form-result ${result==='W'?'win':result==='L'?'loss':'draw'}`;node.textContent=result;node.title=`${arenaName(match.arena)} · ${playlistName(match.playlist_id)}`;strip.appendChild(node);});formView.appendChild(strip);
      const wins=entries.filter(({match,player})=>winnerTeam(match)===safeNumber(player.team)).length,losses=entries.filter(({match,player})=>winnerTeam(match)>=0&&winnerTeam(match)!==safeNumber(player.team)).length,summary=document.createElement('div');summary.className='summary-grid wide';const sum=field=>entries.reduce((value,item)=>value+safeNumber(item.player[field]),0);summary.append(ratioCard('Recent record',`${wins}W · ${losses}L`,`${Math.round(wins/entries.length*100)}% win rate · ${entries.length} matches`),ratioCard('Average score',displayNumber(sum('score')/entries.length),`${sum('score')} total`),ratioCard('Goal involvement',displayNumber((sum('goals')+sum('assists'))/entries.length,2),'per match'),ratioCard('Average saves',displayNumber(sum('saves')/entries.length,2),`${sum('saves')} total`));formView.appendChild(summary);
      formView.appendChild(trendCard('Score trend',entries.slice().reverse().map(item=>safeNumber(item.player.score))));const ranked=entries.slice().reverse().filter(item=>item.player.rank_mmr!=null);if(ranked.length)formView.appendChild(trendCard('MMR trend',ranked.map(item=>safeNumber(item.player.rank_mmr))));
      const records=card('Personal records');const best=field=>entries.reduce((winner,item)=>!winner||safeNumber(item.player[field])>safeNumber(winner.player[field])?item:winner,null),list=document.createElement('div');list.className='status-list';[['Highest score','score'],['Most goals','goals'],['Most saves','saves'],['Most shots','shots'],['Most demos','demos']].forEach(([label,field])=>{const item=best(field),row=document.createElement('div');row.className='status-item';row.innerHTML='<span></span><b></b>';row.firstChild.textContent=label;row.lastChild.textContent=item?`${displayNumber(item.player[field])} · ${arenaName(item.match.arena)}`:'—';list.appendChild(row);});records.appendChild(list);formView.appendChild(records);
      const history=card('Last ten matches');const table=document.createElement('table');table.className='mini-table';table.innerHTML='<thead><tr><th>Match</th><th>Score</th><th>G</th><th>A</th><th>S</th><th>Shots</th><th>MMR</th></tr></thead><tbody></tbody>';entries.forEach(({match,player})=>{const row=document.createElement('tr');const winner=winnerTeam(match),result=winner<0?'D':winner===safeNumber(player.team)?'W':'L';[`${result} · ${playlistName(match.playlist_id)}`,player.score,player.goals,player.assists,player.saves,player.shots,player.rank_mmr==null?'—':Math.round(player.rank_mmr)].forEach(value=>{const cell=document.createElement('td');cell.textContent=value;row.appendChild(cell);});table.tBodies[0].appendChild(row);});history.appendChild(table);formView.appendChild(history);
    }

    function appendPlayerExtras(match,player) {
      const boost=card('Boost management');boost.append(ratioCard('Average boost',displayNumber(player.average_boost,1),`${Math.round(safeNumber(player.low_boost_percent))}% low · ${Math.round(safeNumber(player.empty_boost_percent))}% empty`),ratioCard('Boost used',displayNumber(player.boost_used),`${displayNumber(player.boost_collected)} collected`));boost.classList.add('wide');ratios.appendChild(boost);
      const activity=card('Activity and control');const list=document.createElement('div');list.className='status-list';[['Activity',`${Math.round(safeNumber(player.activity_percent))}%`],['Grounded',`${Math.round(safeNumber(player.grounded_percent))}%`],['Average speed',displayNumber(player.average_speed,1)],['Touches',displayNumber(player.touches)]].forEach(([label,value])=>{const row=document.createElement('div');row.className='status-item';row.innerHTML='<span></span><b></b>';row.firstChild.textContent=label;row.lastChild.textContent=value;list.appendChild(row);});activity.appendChild(list);ratios.appendChild(activity);
      const loadout=card('Loadout');const grid=document.createElement('div');grid.className='loadout-grid';Object.entries(player.loadout||{}).forEach(([name,value])=>{const item=document.createElement('div');item.className='loadout-item';item.innerHTML='<small></small><span></span>';item.firstChild.textContent=name.replace('_',' ');item.lastChild.textContent=value;grid.appendChild(item);});loadout.appendChild(grid);ratios.appendChild(loadout);
    }
    function renderMatch(match, index, count, tab) {
      document.getElementById('match-position').textContent = `Match ${index} of ${count}`;
      navButtons[0].disabled = index <= 1;
      navButtons[1].disabled = index >= count;
      const heading = document.getElementById('match-heading'); heading.textContent = '';
      const title = document.createElement('div'); title.innerHTML = '<div class="arena"></div><div class="meta"></div>'; title.children[0].textContent = arenaName(match.arena); title.children[1].textContent = `${match.played_at || ''} · ${playlistName(match.playlist_id)} · ${match.result || 'Completed'}`; heading.appendChild(title);
      const score = document.createElement('div'); score.className = 'score'; (match.teams || []).forEach(team => { const item = document.createElement('div'); item.className = `team-score team-${safeNumber(team.team)}`; item.textContent = team.name || `Team ${team.team}`; const value = document.createElement('b'); value.textContent = safeNumber(team.score); item.appendChild(value); score.appendChild(item); }); heading.appendChild(score);

      renderFinalScoreboard(match);
      renderOverview(match, index);
      renderTimeline(match);
      renderAnalytics(match);
      renderTeams(match);
      renderForm(latestMessage.matches || []);
      const views={scoreboard,overview,timeline:timelineShell,ratios,teams:teamsView,form:formView};Object.entries(views).forEach(([name,node])=>node.classList.toggle('hidden',tab!==name));const tabs={scoreboard:scoreboardTab,overview:overviewTab,timeline:timelineTab,ratios:ratiosTab,teams:teamsTab,form:formTab};Object.entries(tabs).forEach(([name,node])=>node.classList.toggle('active',tab===name));
      if (tab === 'timeline') requestAnimationFrame(updateTimelineButtons);
    }

    function updateTimelineButtons() {
      const maximum = Math.max(0, timeline.scrollWidth - timeline.clientWidth);
      timelineLeft.disabled = timeline.scrollLeft <= 2;
      timelineRight.disabled = maximum <= 2 || timeline.scrollLeft >= maximum - 2;
    }

    function scrollTimeline(direction, smooth) {
      const distance = Math.max(260, timeline.clientWidth * .72) * direction;
      timeline.scrollBy({left:distance, behavior:smooth ? 'smooth' : 'auto'});
      window.setTimeout(updateTimelineButtons, smooth ? 320 : 0);
    }

    let timelineHoldTimer = 0;
    function startTimelineHold(button, direction, pointerEvent) {
      window.clearInterval(timelineHoldTimer);
      scrollTimeline(direction, true);
      timelineHoldTimer = window.setInterval(() => scrollTimeline(direction, false), 90);
      if (button.setPointerCapture && pointerEvent.pointerId !== undefined) button.setPointerCapture(pointerEvent.pointerId);
    }
    function stopTimelineHold() { window.clearInterval(timelineHoldTimer); timelineHoldTimer = 0; }

    function showAnalysisHint() {
      if (analysisHintShown) return;
      analysisHintShown = true;
      window.clearTimeout(analysisHintTimer);
      analysisHint.classList.remove('hidden', 'hint-out');
      void analysisHint.offsetWidth;
      analysisHintTimer = window.setTimeout(() => {
        analysisHint.classList.add('hint-out');
        window.setTimeout(() => analysisHint.classList.add('hidden'), 230);
      }, 2000);
    }

    let pointerRegionFrame = 0;
    function refreshPointerRegion() {
      if (pointerRegionFrame) cancelAnimationFrame(pointerRegionFrame);
      pointerRegionFrame = requestAnimationFrame(() => {
        pointerRegionFrame = 0;
        const target = localOpen || panelClosing ? panel : latestMessage.visible ? launcher : null;
        const rect = target && !target.classList.contains('hidden') ? target.getBoundingClientRect() : null;
        window.parent.postMessage({
          __hebnixPointerHit: true,
          hit: false,
          region: rect && rect.width > 0 && rect.height > 0
            ? { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom }
            : null
        }, '*');
      });
    }
    function openPanel() {
      if (!latestMessage.visible) return;
      window.clearTimeout(closeTimer);
      panelClosing = false;
      localOpen = true;
      panel.classList.remove('hidden', 'panel-closing', 'panel-opening');
      launcher.classList.add('hidden');
      render(latestMessage);
      void panel.offsetWidth;
      panel.classList.add('panel-opening');
      window.setTimeout(() => panel.classList.remove('panel-opening'), 240);
      requestAnimationFrame(() => { if (localOpen && latestMessage.visible) panel.classList.remove('hidden'); });
    }

    function closePanel() {
      if (!localOpen || panelClosing) return;
      window.clearTimeout(closeTimer);
      localOpen = false;
      panelClosing = true;
      analysisHint.classList.add('hidden');
      panel.classList.remove('panel-opening');
      panel.classList.add('panel-closing');
      launcher.classList.add('hidden');
      closeTimer = window.setTimeout(() => {
        panelClosing = false;
        panel.classList.remove('panel-closing');
        render(latestMessage);
        if (latestMessage.visible) {
          launcher.classList.remove('launcher-enter');
          void launcher.offsetWidth;
          launcher.classList.add('launcher-enter');
          window.setTimeout(() => launcher.classList.remove('launcher-enter'), 200);
        }
      }, 190);
    }

    function render(message) {
      latestMessage = message || latestMessage;
      const visible = Boolean(latestMessage.visible); const matches = Array.isArray(latestMessage.matches) ? latestMessage.matches : [];
      if (!visible) {
        window.clearTimeout(closeTimer);
        localOpen = false; panelClosing = false;
        launcher.classList.add('hidden'); panel.classList.add('hidden'); panel.classList.remove('panel-opening', 'panel-closing');
        refreshPointerRegion();
        return;
      }
      localMatch = Math.max(1, Math.min(Math.max(1, matches.length), localMatch));
      launcher.classList.toggle('hidden', localOpen || panelClosing);
      panel.classList.toggle('hidden', !localOpen && !panelClosing);
      refreshPointerRegion();
      if (!localOpen) return;
      const index = Math.min(matches.length, localMatch); const match = matches[index - 1];
      empty.classList.toggle('hidden', Boolean(match)); content.classList.toggle('hidden', !match); document.getElementById('match-position').textContent = match ? `Match ${index} of ${matches.length}` : 'Match 0 of 0';
      navButtons.forEach(button => { button.disabled = !match; });
      if (match) renderMatch(match, index, matches.length, localTab);
    }
    launcher.addEventListener('click', openPanel);
    closeButton.addEventListener('click', closePanel);
    scoreboardTab.addEventListener('click', () => { localTab = 'scoreboard'; render(latestMessage); });
    overviewTab.addEventListener('click', () => { localTab = 'overview'; render(latestMessage); });
    timelineTab.addEventListener('click', () => { localTab = 'timeline'; render(latestMessage); });
    ratiosTab.addEventListener('click', () => { localTab = 'ratios'; render(latestMessage); showAnalysisHint(); });
    teamsTab.addEventListener('click', () => { localTab = 'teams'; render(latestMessage); });
    formTab.addEventListener('click', () => { localTab = 'form'; render(latestMessage); });
    timeline.addEventListener('scroll', updateTimelineButtons, {passive:true});
    timelineLeft.addEventListener('pointerdown', event => startTimelineHold(timelineLeft, -1, event));
    timelineRight.addEventListener('pointerdown', event => startTimelineHold(timelineRight, 1, event));
    [timelineLeft, timelineRight].forEach(button => { button.addEventListener('pointerup', stopTimelineHold); button.addEventListener('pointercancel', stopTimelineHold); button.addEventListener('pointerleave', stopTimelineHold); });
    navButtons[0].addEventListener('click', () => { localMatch = Math.max(1, localMatch - 1); timeline.scrollLeft = 0; render(latestMessage); });
    navButtons[1].addEventListener('click', () => { localMatch += 1; timeline.scrollLeft = 0; render(latestMessage); });
    window.addEventListener('message', event => render(event.data || {}));
